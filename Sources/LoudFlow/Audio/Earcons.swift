import Foundation
import AVFoundation

/// The app's three sounds, synthesized rather than shipped as files.
///
/// Each is a **triangle** wave with a 4ms linear attack and a linear decay to true zero, run
/// through a lowpass at 3× the fundamental to take the edge off the harmonics. The decay is
/// linear on purpose: an exponential tail reads as an echo.
///
/// There is no setting. Sounds are on.
@MainActor
enum Earcons {

    /// Record starts — 784 Hz, 70ms.
    static func recordStart() { play([Tone(hz: 784, ms: 70, gain: 0.30, delayMs: 0)]) }

    /// Record stops — 523 Hz, 70ms.
    static func recordStop() { play([Tone(hz: 523, ms: 70, gain: 0.30, delayMs: 0)]) }

    /// Transcript lands — 1046 Hz then 1318 Hz, 50ms and 80ms, 55ms apart.
    static func transcriptLanded() {
        play([
            Tone(hz: 1046, ms: 50, gain: 0.22, delayMs: 0),
            Tone(hz: 1318, ms: 80, gain: 0.26, delayMs: 55),
        ])
    }

    // MARK: - Synthesis

    private struct Tone {
        let hz: Double
        let ms: Double
        let gain: Double
        let delayMs: Double     // from the start of the earcon
    }

    private static let sampleRate: Double = 44_100
    private static let attack: Double = 0.004      // 4ms

    private static let engine = AVAudioEngine()
    private static let node = AVAudioPlayerNode()
    private static var started = false

    private static func play(_ tones: [Tone]) {
        guard let buffer = render(tones) else { return }
        guard start() else { return }
        node.scheduleBuffer(buffer, at: nil, options: [])
        node.play()
    }

    private static func start() -> Bool {
        if started { return engine.isRunning || (try? engine.start()) != nil }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return false }
        started = true
        return true
    }

    private static func render(_ tones: [Tone]) -> AVAudioPCMBuffer? {
        let total = tones.map { ($0.delayMs + $0.ms) / 1000 }.max() ?? 0
        let frames = AVAudioFrameCount((total + 0.02) * sampleRate)   // a little tail of silence
        guard frames > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0]
        else { return nil }

        buffer.frameLength = frames
        for i in 0..<Int(frames) { samples[i] = 0 }

        for tone in tones {
            let start = Int(tone.delayMs / 1000 * sampleRate)
            let count = Int(tone.ms / 1000 * sampleRate)
            guard count > 0 else { continue }

            // One-pole lowpass at 3× the fundamental, run over this tone only.
            let cutoff = min(tone.hz * 3, sampleRate / 2 - 1)
            let a = 1 - exp(-2 * Double.pi * cutoff / sampleRate)
            var lp = 0.0
            var phase = 0.0
            let step = tone.hz / sampleRate
            let duration = tone.ms / 1000

            for n in 0..<count {
                let idx = start + n
                guard idx < Int(frames) else { break }
                let t = Double(n) / sampleRate

                // Triangle: +1 at the zero phase, −1 at the half.
                let tri = 4 * abs(phase - 0.5) - 1
                phase += step
                if phase >= 1 { phase -= 1 }

                lp += a * (tri - lp)

                // 4ms linear attack, then a straight line down to true zero.
                let env: Double
                if t < attack {
                    env = t / attack
                } else {
                    env = max(0, 1 - (t - attack) / max(0.0001, duration - attack))
                }

                samples[idx] += Float(lp * env * tone.gain)
            }
        }
        return buffer
    }
}
