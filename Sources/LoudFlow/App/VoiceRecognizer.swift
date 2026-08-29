import Foundation
import AVFoundation
import FluidAudio

/// Recognises a voice you have already named when it turns up in a later recording.
///
/// The provider's diarization only separates voices **within** one recording — it has no idea
/// that speaker 1 today is the same person as speaker 1 last Tuesday. This closes that gap
/// locally: a named voice gets a 256-dimensional embedding (a voice fingerprint) computed on
/// this Mac, and a new recording's speakers are compared against the ones already stored.
///
/// The split of labour is deliberate. Deepgram still says *when* each speaker spoke; this only
/// answers *who they are*, and it answers it on-device — no audio leaves the Mac for this step.
///
/// **It refuses to guess.** A match has to be both close and clearly closer than the runner-up,
/// or the voice stays `Speaker 2` for you to name yourself. A wrong name on a transcript is
/// worse than no name.
///
/// The CoreML models (pyannote segmentation + a WeSpeaker embedder) are fetched once, the first
/// time a voice is named, and cached on disk from then on.
@MainActor
final class VoiceRecognizer: ObservableObject {

    enum Readiness: Equatable {
        case idle           // nothing needed yet
        case preparing      // fetching / compiling the models
        case ready
        case unavailable    // no network on first use, or the models wouldn't load
    }

    @Published private(set) var readiness: Readiness = .idle

    private var diarizer: DiarizerManager?
    private var preparing: Task<Bool, Never>?

    /// Maximum cosine distance that still counts as the same person. Stricter than the
    /// library's clustering default (0.65), because clustering can afford a wrong guess and a
    /// name written on a transcript cannot.
    private static let matchDistance: Float = 0.45

    /// The second-best candidate has to be at least this much further away. Two people who both
    /// look like a weak match means we don't actually know which, so we say nothing.
    private static let requiredMargin: Float = 0.08

    /// How much of a speaker's audio to feed the embedder. More is steadier; past a few seconds
    /// it stops helping and only costs time.
    private static let maxSeconds: Double = 12

    // MARK: - Model loading

    /// Loads the models if they aren't loaded yet. Safe to call repeatedly; concurrent callers
    /// wait on the same attempt.
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

    // MARK: - Embedding

    /// A voice fingerprint for one speaker in one clip, or nil when there isn't enough of them
    /// to be sure about.
    func embedding(forSpeaker speaker: Int, in clip: Clip) async -> [Float]? {
        guard !clip.audioDeleted, await prepare(), let diarizer else { return nil }
        guard let samples = Self.samples(forSpeaker: speaker, in: clip), samples.count >= 16_000
        else { return nil }
        return try? diarizer.extractSpeakerEmbedding(from: samples)
    }

    // MARK: - Matching

    /// The stored voice this embedding belongs to, or nil when nothing is a confident match.
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
            return nil          // two plausible people — don't pick one
        }
        return best.id
    }

    /// Embeddings come back L2-normalised, so the dot product is the cosine similarity.
    private static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        var dot: Float = 0
        for i in 0..<min(a.count, b.count) { dot += a[i] * b[i] }
        return 1 - max(-1, min(1, dot))
    }

    // MARK: - Pulling one speaker's audio out of a clip

    /// Every stretch this speaker holds the floor, concatenated, as 16 kHz mono samples.
    ///
    /// Two-track recordings keep you on channel 0 and the call on channel 1, so the right
    /// channel is picked rather than mixed — the other side's voice never has yours over it.
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

    /// Linear resample. The app writes its own clips at 16 kHz, so this only ever runs on
    /// recordings made before that was true.
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
