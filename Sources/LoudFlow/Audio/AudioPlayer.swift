import Foundation
import AVFoundation

/// Plays one clip at a time, reporting progress (0…1) and completion.
///
/// The playhead belongs to the clip, not to the player: pausing keeps the position, pressing
/// play again resumes from it, and reaching the end leaves the position at the end rather than
/// snapping back to zero. `AppModel` stores the fraction per clip so the scrubber can show it
/// even when nothing is playing.
final class AudioPlayer: NSObject {
    var onProgress: ((Double) -> Void)?
    var onFinish: (() -> Void)?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var isPlaying: Bool { player?.isPlaying ?? false }
    var duration: TimeInterval { player?.duration ?? 0 }

    /// Starts (or resumes) `url` at `fraction` of its length.
    func play(url: URL, from fraction: Double = 0) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { onFinish?(); return }
        p.delegate = self
        player = p
        // A clip played to the end starts over rather than refusing to move.
        let start = fraction >= 0.999 ? 0 : max(0, min(1, fraction))
        p.currentTime = start * p.duration
        p.play()
        onProgress?(start)
        startTicking()
    }

    /// Stops the audio but leaves the reported position where it is.
    func pause() {
        timer?.invalidate(); timer = nil
        player?.pause()
    }

    func resume() {
        guard let p = player else { return }
        p.play()
        startTicking()
    }

    /// Moves the playhead of whatever is loaded. Safe to call while paused.
    func seek(to fraction: Double) {
        guard let p = player, p.duration > 0 else { return }
        p.currentTime = max(0, min(1, fraction)) * p.duration
        onProgress?(max(0, min(1, fraction)))
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
    }

    private func startTicking() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, p.duration > 0 else { return }
            self.onProgress?(min(1, p.currentTime / p.duration))
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        timer?.invalidate(); timer = nil
        self.player = nil
        onProgress?(1)      // the knob stays at the end
        onFinish?()
    }
}
