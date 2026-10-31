import Foundation
import AVFoundation

final class AudioRecorder: NSObject {

    struct Outcome {
        let duration: TimeInterval
        let twoTrack: Bool
        // Another app played audio, but none of it reached the call track.
        var callAudioMissed = false
    }

    private let engine = AVAudioEngine()
    private var micFile: AVAudioFile?
    private var system: Any?
    private var startedAt: Date?
    private var target: URL?
    private var micScratch: URL?
    private var systemScratch: URL?
    private(set) var isRecording = false

    private let clock = NSLock()
    private var micStartHostTime: UInt64?
    private var othersPlayedAudio = false

    private static let outputRate: Double = 16_000

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

        clock.lock(); micStartHostTime = nil; clock.unlock()
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, when in
            guard let self, let f = self.micFile else { return }
            self.noteMicStart(when)
            try? f.write(from: Self.mono(buffer, as: f.processingFormat))
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

        if #available(macOS 14.2, *) {
            othersPlayedAudio = SystemAudioTap.othersArePlaying()
            let tap = SystemAudioTap()

            system = tap.start(to: sys) ? tap : nil
        }
    }

    func stop() async -> Outcome {
        guard isRecording else { return Outcome(duration: 0, twoTrack: false) }
        isRecording = false

        let duration = startedAt.map { Date().timeIntervalSince($0) } ?? 0
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        micFile = nil

        var systemTrack: URL?
        var systemDelay: TimeInterval = 0
        var callAudioMissed = false
        if #available(macOS 14.2, *) {
            let othersPlayed = othersPlayedAudio || SystemAudioTap.othersArePlaying()
            if let tap = system as? SystemAudioTap {
                tap.stop()
                if tap.capturedAnything {
                    systemTrack = systemScratch
                    systemDelay = delay(of: tap.startHostTime)
                }
            }
            callAudioMissed = othersPlayed && systemTrack == nil
        }
        system = nil

        defer { cleanScratch() }
        guard let target, let mic = micScratch else {
            return Outcome(duration: duration, twoTrack: false)
        }

        let twoTrack = Self.encode(mic: mic, system: systemTrack, systemDelay: systemDelay, to: target)
        return Outcome(duration: duration, twoTrack: twoTrack, callAudioMissed: callAudioMissed && !twoTrack)
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

    private func noteMicStart(_ when: AVAudioTime) {
        guard when.isHostTimeValid else { return }
        clock.lock()
        if micStartHostTime == nil { micStartHostTime = when.hostTime }
        clock.unlock()
    }

    // The system tap starts a beat after the mic. Without this, the far side's words land early.
    private func delay(of systemStart: UInt64?) -> TimeInterval {
        clock.lock(); let micStart = micStartHostTime; clock.unlock()
        guard let micStart, let systemStart else { return 0 }
        let delay = AVAudioTime.seconds(forHostTime: systemStart) - AVAudioTime.seconds(forHostTime: micStart)
        return max(-2, min(2, delay))
    }

    // A file opened as mono rejects multi-channel buffers, which left interface mics silent.
    private static func mono(_ buffer: AVAudioPCMBuffer, as format: AVAudioFormat) -> AVAudioPCMBuffer {
        let channels = Int(buffer.format.channelCount)
        guard channels > 1, let source = buffer.floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: buffer.frameLength),
              let target = out.floatChannelData?[0]
        else { return buffer }
        out.frameLength = buffer.frameLength
        let scale = 1 / Float(channels)
        for i in 0..<Int(buffer.frameLength) {
            var sum: Float = 0
            for c in 0..<channels { sum += source[c][i] }
            target[i] = sum * scale
        }
        return out
    }

    private static func encode(mic: URL, system: URL?, systemDelay: TimeInterval, to target: URL) -> Bool {
        guard let monoFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: 1),
              let micSamples = resampled(mic, to: monoFormat)
        else { return false }

        let systemSamples = system.flatMap { resampled($0, to: monoFormat) }
        let channels: AVAudioChannelCount = systemSamples == nil ? 1 : 2
        let shift = Int((systemDelay * outputRate).rounded())
        let systemEnd = systemSamples.map { max(0, Int($0.frameLength) + shift) } ?? 0
        let frames = max(micSamples.frameLength, AVAudioFrameCount(systemEnd))
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
        copy(micSamples, into: data[0], frames: frames, shift: 0)
        if channels == 2, let systemSamples {
            copy(systemSamples, into: data[1], frames: frames, shift: shift)
        }

        guard (try? out.write(from: buffer)) != nil else { return false }
        return channels == 2
    }

    // A positive shift delays the source; a negative one drops its first frames.
    private static func copy(_ source: AVAudioPCMBuffer, into destination: UnsafeMutablePointer<Float>,
                             frames: AVAudioFrameCount, shift: Int) {
        let total = Int(frames)
        destination.update(repeating: 0, count: total)
        guard let src = source.floatChannelData?[0] else { return }
        let skip = max(0, -shift)
        let offset = max(0, shift)
        let count = min(Int(source.frameLength) - skip, total - offset)
        guard count > 0 else { return }
        (destination + offset).update(from: src + skip, count: count)
    }

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
