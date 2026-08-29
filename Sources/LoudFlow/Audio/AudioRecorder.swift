import Foundation
import AVFoundation

/// Records the microphone to an `.m4a` (AAC) file on disk. Real file size drives `sizeMB`.
///
/// The widget's waveform is decorative (a fixed CSS-style animation), so no live metering is
/// surfaced — the spec is explicit that nothing live is shown while recording.
final class AudioRecorder: NSObject {
    private var recorder: AVAudioRecorder?
    private var startedAt: Date?

    var isRecording: Bool { recorder?.isRecording ?? false }

    func start(to url: URL) throws {
        // 16 kHz mono AAC is plenty for speech and keeps clips small + upload-fast.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let r = try AVAudioRecorder(url: url, settings: settings)
        r.delegate = self
        guard r.record() else { throw RecorderError.couldNotStart }
        recorder = r
        startedAt = Date()
    }

    /// Stops and returns the recorded duration in seconds.
    @discardableResult
    func stop() -> TimeInterval {
        let duration = recorder?.currentTime ?? startedAt.map { Date().timeIntervalSince($0) } ?? 0
        recorder?.stop()
        recorder = nil
        startedAt = nil
        return duration
    }

    func cancel() {
        recorder?.stop()
        if let url = recorder?.url { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        startedAt = nil
    }

    enum RecorderError: Error { case couldNotStart }
}

extension AudioRecorder: AVAudioRecorderDelegate {}
