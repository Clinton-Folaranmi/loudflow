import Foundation
import AVFoundation

/// Records a clip as **two tracks**: the microphone on channel 0 and whatever the Mac is
/// playing on channel 1.
///
/// That split is the point. Because your voice arrives on its own channel, speaker 0 is always
/// you — the provider never has to guess — and diarization only has to divide the remote side.
/// It is not a setting and there is no meeting mode: a recording with one voice in it is a
/// note, a recording with several is a conversation, and that is decided afterwards by what was
/// actually heard.
///
/// System audio is captured with a Core Audio process tap (see `SystemAudioTap`), which asks
/// for audio-capture permission and nothing else. When that isn't granted, or nothing was
/// playing, the clip is written as a plain mono file and everything downstream still works.
///
/// Nothing live is surfaced while recording — the widget shows a dot and a timer, per the spec.
final class AudioRecorder: NSObject {

    struct Outcome {
        let duration: TimeInterval
        /// True when the finished file really has two distinct channels.
        let twoTrack: Bool
    }

    private let engine = AVAudioEngine()
    private var micFile: AVAudioFile?
    private var system: Any?              // SystemAudioTap on macOS 14.2+
    private var startedAt: Date?
    private var target: URL?
    private var micScratch: URL?
    private var systemScratch: URL?
    private(set) var isRecording = false

    /// Encoded output: 16 kHz is plenty for speech and keeps clips small and upload-fast.
    private static let outputRate: Double = 16_000

    // MARK: - Start

    func start(to url: URL) throws {
        guard !isRecording else { return }

        let stem = url.deletingPathExtension()
        let mic = stem.appendingPathExtension("mic.caf")
        let sys = stem.appendingPathExtension("sys.caf")
        try? FileManager.default.removeItem(at: mic)
        try? FileManager.default.removeItem(at: sys)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecorderError.couldNotStart }

        let file = try AVAudioFile(forWriting: mic, settings: [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ])
        micFile = file

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self, let f = self.micFile else { return }
            try? f.write(from: buffer)
        }

        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            micFile = nil
            throw RecorderError.couldNotStart
        }

        target = url
        micScratch = mic
        systemScratch = sys
        startedAt = Date()
        isRecording = true

        // The other half of the call. Best-effort: a refusal here just means a mono clip.
        if #available(macOS 14.2, *) {
            let tap = SystemAudioTap()
            system = tap.start(to: sys) ? tap : nil
        }
    }

    // MARK: - Stop

    /// Stops both tracks, encodes them into the clip's `.m4a`, and reports what was captured.
    func stop() async -> Outcome {
        guard isRecording else { return Outcome(duration: 0, twoTrack: false) }
        isRecording = false

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micFile = nil

        var systemTrack: URL?
        if #available(macOS 14.2, *), let tap = system as? SystemAudioTap {
            tap.stop()
            if tap.capturedAnything { systemTrack = systemScratch }
        }
        system = nil

        defer { cleanScratch() }
        guard let target, let mic = micScratch else {
            return Outcome(duration: duration, twoTrack: false)
        }

        let twoTrack = Self.encode(mic: mic, system: systemTrack, to: target)
        return Outcome(duration: duration, twoTrack: twoTrack)
    }

    func cancel() {
        guard isRecording else { return }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micFile = nil
        if #available(macOS 14.2, *), let tap = system as? SystemAudioTap { tap.stop() }
        system = nil
        if let target { try? FileManager.default.removeItem(at: target) }
        cleanScratch()
        startedAt = nil
    }

    private func cleanScratch() {
        [micScratch, systemScratch].compactMap { $0 }.forEach {
            try? FileManager.default.removeItem(at: $0)
        }
        micScratch = nil
        systemScratch = nil
        target = nil
        startedAt = nil
    }

    // MARK: - Encoding

    /// Writes the AAC clip. Two channels when there is real system audio to put on channel 1,
    /// one when there isn't. Returns whether the file ended up two-track.
    private static func encode(mic: URL, system: URL?, to target: URL) -> Bool {
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1),
              let micSamples = resampled(mic, to: monoFormat)
        else { return false }

        let systemSamples = system.flatMap { resampled($0, to: monoFormat) }
        let channels: AVAudioChannelCount = systemSamples == nil ? 1 : 2
        let frames = max(micSamples.frameLength, systemSamples?.frameLength ?? 0)
        guard frames > 0 else { return false }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: outputRate,
            AVNumberOfChannelsKey: Int(channels),
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        try? FileManager.default.removeItem(at: target)
        guard let out = try? AVAudioFile(forWriting: target, settings: settings),
              let buffer = AVAudioPCMBuffer(pcmFormat: out.processingFormat, frameCapacity: frames),
              let data = buffer.floatChannelData
        else { return false }

        buffer.frameLength = frames
        copy(micSamples, into: data[0], frames: frames)
        if channels == 2, let systemSamples {
            copy(systemSamples, into: data[1], frames: frames)
        }

        guard (try? out.write(from: buffer)) != nil else { return false }
        return channels == 2
    }

    private static func copy(_ source: AVAudioPCMBuffer, into destination: UnsafeMutablePointer<Float>,
                             frames: AVAudioFrameCount) {
        let available = Int(min(source.frameLength, frames))
        if let src = source.floatChannelData?[0] {
            destination.update(from: src, count: available)
        }
        for i in available..<Int(frames) { destination[i] = 0 }
    }

    /// Reads a whole scratch track and resamples it to the output format, downmixing to mono.
    private static func resampled(_ url: URL, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return nil }
        let sourceFormat = file.processingFormat
        guard let source = AVAudioPCMBuffer(pcmFormat: sourceFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: source)) != nil
        else { return nil }

        if sourceFormat.sampleRate == format.sampleRate && sourceFormat.channelCount == 1 {
            return source
        }
        let ratio = format.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(source.frameLength) * ratio) + 1024
        guard let converter = AVAudioConverter(from: sourceFormat, to: format),
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { return nil }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .endOfStream; return nil }
            supplied = true
            status.pointee = .haveData
            return source
        }
        return error == nil ? out : nil
    }

    enum RecorderError: Error { case couldNotStart }
}
