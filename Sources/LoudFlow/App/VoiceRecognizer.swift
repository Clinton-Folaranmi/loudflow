import Foundation
import AVFoundation
import FluidAudio

@MainActor
final class VoiceRecognizer: ObservableObject {

    enum Readiness: Equatable {
        case idle
        case preparing
        case ready
        case unavailable
    }

    @Published private(set) var readiness: Readiness = .idle

    private var diarizer: DiarizerManager?
    private var preparing: Task<Bool, Never>?

    // Keep uncertain matches for manual review.
    private static let matchDistance: Float = 0.45
    private static let requiredMargin: Float = 0.08

    // The embedder hears a 10 s window and cuts off the rest.
    private static let maxSeconds: Double = 10
    private static let minSeconds: Double = 1
    private static let rate: Double = 16_000

    @discardableResult
    func prepare() async -> Bool {
        if diarizer != nil { return true }
        if let preparing { return await preparing.value }

        readiness = .preparing
        let task = Task<Bool, Never> { [weak self] in
            do {
                let models = try await DiarizerModels.downloadIfNeeded()
                let manager = DiarizerManager()
                manager.initialize(models: models)
                await MainActor.run {
                    self?.diarizer = manager
                    self?.readiness = .ready
                }
                return true
            } catch {
                await MainActor.run { self?.readiness = .unavailable }
                return false
            }
        }
        preparing = task
        let ok = await task.value
        preparing = nil
        return ok
    }

    func embedding(forSpeaker speaker: Int, in clip: Clip) async -> [Float]? {
        guard !clip.audioDeleted, let turns = clip.turns else { return nil }
        var spans: [(from: TimeInterval, to: TimeInterval)] = []
        for (i, turn) in turns.enumerated() where turn.speaker == speaker {
            let next = i + 1 < turns.count ? turns[i + 1].at : Double(clip.seconds)
            let to = turn.end ?? next
            if to > turn.at { spans.append((turn.at, to)) }
        }
        // Long turns are cleaner than a word here and there.
        spans.sort { $0.to - $0.from > $1.to - $1.from }
        let channel = speaker == Voice.youID || !clip.twoTrack ? 0 : 1
        return await embed(clip, channel: channel, spans: spans)
    }

    func embedding(ofSoloClip clip: Clip) async -> [Float]? {
        guard !clip.audioDeleted, !clip.isConversation else { return nil }
        // The start earcon can leak into the first moment of the mic.
        return await embed(clip, channel: 0, spans: [(0.4, Double(clip.seconds))])
    }

    func match(_ embedding: [Float], against voices: [Voice],
               includingYou: Bool) -> (id: Int, distance: Float)? {
        let candidates: [(id: Int, distance: Float)] = voices.compactMap { voice in
            guard voice.isNamed, includingYou || !voice.isYou, let known = voice.embedding,
                  known.count == embedding.count
            else { return nil }
            return (voice.id, Self.cosineDistance(embedding, known))
        }
        .sorted { $0.distance < $1.distance }

        guard let best = candidates.first, best.distance <= Self.matchDistance else { return nil }
        if let runnerUp = candidates.dropFirst().first,
           runnerUp.distance - best.distance < Self.requiredMargin {
            return nil
        }
        return best
    }

    func isConsistent(_ embedding: [Float], with voice: Voice) -> Bool {
        guard let known = voice.embedding, known.count == embedding.count else { return true }
        return Self.cosineDistance(embedding, known) <= Self.matchDistance
    }

    nonisolated static func normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? vector.map { $0 / norm } : vector
    }

    private func embed(_ clip: Clip, channel: Int, spans: [(from: TimeInterval, to: TimeInterval)]) async -> [Float]? {
        guard await prepare(), let diarizer,
              let samples = Self.voicedSamples(of: clip, channel: channel, spans: spans),
              Double(samples.count) >= Self.minSeconds * Self.rate,
              let embedding = try? diarizer.extractSpeakerEmbedding(from: samples),
              embedding.contains(where: { $0 != 0 })
        else { return nil }
        return embedding
    }

    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0, aa: Float = 0, bb: Float = 0
        for i in 0..<min(a.count, b.count) {
            dot += a[i] * b[i]
            aa += a[i] * a[i]
            bb += b[i] * b[i]
        }
        guard aa > 0, bb > 0 else { return 2 }
        return 1 - max(-1, min(1, dot / (aa.squareRoot() * bb.squareRoot())))
    }

    private static func voicedSamples(of clip: Clip, channel: Int,
                                      spans: [(from: TimeInterval, to: TimeInterval)]) -> [Float]? {
        let url = Persistence.shared.url(forAudio: clip.audioFileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url), file.length > 0
        else { return nil }

        let format = file.processingFormat
        let sourceRate = format.sampleRate
        let source = min(channel, Int(format.channelCount) - 1)
        let wanted = Int(maxSeconds * rate)
        // Read only what can fill the window, even from an hour-long span.
        let readCap = AVAudioFramePosition(maxSeconds * 3 * sourceRate)

        var out: [Float] = []
        out.reserveCapacity(wanted)
        for span in spans {
            let start = AVAudioFramePosition(max(0, span.from) * sourceRate)
            let end = min(file.length, start + readCap, AVAudioFramePosition(span.to * sourceRate))
            let count = AVAudioFrameCount(max(0, end - start))
            guard Double(count) >= 0.3 * sourceRate,
                  let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)
            else { continue }
            file.framePosition = start
            guard (try? file.read(into: buffer, frameCount: count)) != nil,
                  let data = buffer.floatChannelData
            else { continue }

            var piece = Array(UnsafeBufferPointer(start: data[source], count: Int(buffer.frameLength)))
            if sourceRate != rate { piece = resample(piece, from: sourceRate, to: rate) }
            out.append(contentsOf: voiced(piece))
            if out.count >= wanted { break }
        }
        guard !out.isEmpty else { return nil }
        return Array(out.prefix(wanted))
    }

    // Drops pauses, so the embedding describes the voice rather than the room.
    private static func voiced(_ samples: [Float]) -> [Float] {
        let frame = Int(rate * 0.02)
        let frames = samples.count / frame
        guard frames >= 5 else { return samples }

        var energy = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var sum: Float = 0
            for i in (f * frame)..<((f + 1) * frame) { sum += samples[i] * samples[i] }
            energy[f] = sum / Float(frame)
        }
        let loud = energy.sorted()[Int(Double(frames - 1) * 0.9)]
        let floor = max(loud * 0.01, 1e-8)

        var out: [Float] = []
        out.reserveCapacity(samples.count)
        for f in 0..<frames where energy[f] >= floor {
            out.append(contentsOf: samples[(f * frame)..<((f + 1) * frame)])
        }
        return out
    }

    private static func resample(_ samples: [Float], from: Double, to: Double) -> [Float] {
        let ratio = to / from
        let count = Int(Double(samples.count) * ratio)
        guard count > 1 else { return samples }
        return (0..<count).map { i in
            let position = Double(i) / ratio
            let low = Int(position)
            let high = min(low + 1, samples.count - 1)
            let t = Float(position - Double(low))
            return samples[low] * (1 - t) + samples[high] * t
        }
    }
}
