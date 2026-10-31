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

    private static let maxSeconds: Double = 12

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
        guard !clip.audioDeleted, await prepare(), let diarizer else { return nil }
        guard let samples = Self.samples(forSpeaker: speaker, in: clip), samples.count >= 16_000
        else { return nil }
        return try? diarizer.extractSpeakerEmbedding(from: samples)
    }

    func match(_ embedding: [Float], against voices: [Voice]) -> Int? {
        let candidates: [(id: Int, distance: Float)] = voices.compactMap { voice in
            guard voice.isNamed, !voice.isYou, let known = voice.embedding,
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
        return best.id
    }

    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i] }
        return 1 - max(-1, min(1, dot))
    }

    private static func samples(forSpeaker speaker: Int, in clip: Clip) -> [Float]? {
        let url = Persistence.shared.url(forAudio: clip.audioFileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let file = try? AVAudioFile(forReading: url), file.length > 0,
              let turns = clip.turns
        else { return nil }

        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil,
              let channels = buffer.floatChannelData
        else { return nil }

        let channelIndex = (speaker == Voice.youID || format.channelCount < 2) ? 0 : 1
        let source = channels[min(channelIndex, Int(format.channelCount) - 1)]
        let rate = format.sampleRate
        let total = Int(buffer.frameLength)

        var out: [Float] = []
        out.reserveCapacity(Int(maxSeconds * 16_000))

        for (i, turn) in turns.enumerated() where turn.speaker == speaker {
            let end = i + 1 < turns.count ? turns[i + 1].at : Double(clip.seconds)
            let from = max(0, Int(turn.at * rate))
            let to = min(total, Int(end * rate))
            guard to > from else { continue }
            out.append(contentsOf: UnsafeBufferPointer(start: source + from, count: to - from))
            if Double(out.count) / rate >= maxSeconds { break }
        }
        guard !out.isEmpty else { return nil }

        return rate == 16_000 ? out : resample(out, from: rate, to: 16_000)
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
