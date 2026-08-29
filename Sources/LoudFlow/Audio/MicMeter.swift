import Foundation
import AVFoundation

/// Live microphone level (0…1) for the onboarding mic test — so the bars actually react to
/// your voice instead of playing a canned animation. Records to a throwaway temp file purely
/// to read metering; nothing is kept.
final class MicMeter: ObservableObject {
    @Published var level: Double = 0

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("loudflow-mic-test.caf")

    func start() {
        Permissions.requestMic { [weak self] granted in
            guard granted, let self else { return }
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
            ]
            guard let r = try? AVAudioRecorder(url: self.tempURL, settings: settings) else { return }
            r.isMeteringEnabled = true
            r.record()
            self.recorder = r
            self.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                guard let self, let r = self.recorder else { return }
                r.updateMeters()
                let db = r.averagePower(forChannel: 0)          // roughly -60…0 dB
                let norm = max(0, min(1, Double(db + 55) / 55))  // → 0…1
                self.level = norm
            }
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        recorder?.stop(); recorder = nil
        try? FileManager.default.removeItem(at: tempURL)
        level = 0
    }
}
