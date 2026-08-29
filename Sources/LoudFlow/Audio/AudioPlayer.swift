import Foundation
import AVFoundation

/// Plays one clip at a time, reporting progress (0…1) and completion. Progress advances to
/// 100% then the player clears itself — the row button and the editor's play button both
/// reflect the same state via `AppModel.playingId`.
final class AudioPlayer: NSObject {
    var onProgress: ((Double) -> Void)?
    var onFinish: (() -> Void)?

    private var player: AVAudioPlayer?
    private var timer: Timer?

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(url: URL) {
        stop()
        guard let p = try? AVAudioPlayer(contentsOf: url) else { onFinish?(); return }
        p.delegate = self
        player = p
        p.play()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, let p = self.player, p.duration > 0 else { return }
            self.onProgress?(min(1, p.currentTime / p.duration))
        }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        player?.stop(); player = nil
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        timer?.invalidate(); timer = nil
        self.player = nil
        onProgress?(1)
        onFinish?()
    }
}
