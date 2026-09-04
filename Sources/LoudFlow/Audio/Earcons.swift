import Foundation
import AVFoundation

/// The app's three sounds, synthesized rather than shipped as files.
///
/// Each is a **triangle** wave with a 4ms linear attack and a linear decay to true zero, run
/// through a lowpass at 3× the fundamental to take the edge off the harmonics. The decay is
/// linear on purpose: an exponential tail reads as an echo.
///
/// Each tone plays through its own short-lived `AVAudioPlayer`, not one long-lived
/// `AVAudioEngine`. That used to be an engine + player node kept for the app's whole life, and
/// it went silent the moment `AudioRecorder` started a recording: recording is exactly what
/// fires `AVAudioEngineConfigurationChange` (the mic engine starting, and — with system audio
/// on — `SystemAudioTap` building a private aggregate output device), which tears down the
/// earcon engine's node connections. The engine itself restarted fine on the next tone, so
/// `started` stayed true and nothing ever surfaced an error; the player node was just no
/// longer connected to anything, so the tone played into nowhere. `AVAudioPlayer` has no such
/// failure mode — it owns its own output and re-establishes it across a device change on its
/// own — so a rendered tone is decoded to a small WAV `Data` once and replayed from a cached
/// player from then on.
///
/// There is no setting. Sounds are on.
@MainActor
enum Earcons {

    /// Record starts — 784 Hz, 70ms.
    static func recordStart() { play(.recordStart, [Tone(hz: 784, ms: 70, gain: 0.30, delayMs: 0)]) }

    /// Record stops — 523 Hz, 70ms.
    static func recordStop() { play(.recordStop, [Tone(hz: 523, ms: 70, gain: 0.30, delayMs: 0)]) }

    /// Transcript lands — 1046 Hz then 1318 Hz, 50ms and 80ms, 55ms apart.
    static func transcriptLanded() {
        play(.transcriptLanded, [
            Tone(hz: 1046, ms: 50, gain: 0.22, delayMs: 0),
            Tone(hz: 1318, ms: 80, gain: 0.26, delayMs: 55),
        ])
    }

    // MARK: - Playback

    private enum Sound { case recordStart, recordStop, transcriptLanded }

    /// One player per sound, built the first time it's needed and replayed from the start every
    /// time after — `currentTime = 0; play()` rather than a fresh player per call, so a rapid
    /// start/stop/start doesn't pile up players.
    private static var players: [Sound: AVAudioPlayer] = [:]

    private static func play(_ sound: Sound, _ tones: [Tone]) {
        let player: AVAudioPlayer
        if let cached = players[sound] {
            player = cached
        } else {
            guard let buffer = render(tones),
                  let data = wavData(from: buffer),
                  let created = try? AVAudioPlayer(data: data)
            else { return }
            created.prepareToPlay()
            players[sound] = created
            player = created
        }
        player.currentTime = 0
        player.play()
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

    // MARK: - Buffer → WAV

    /// A minimal 16-bit-PCM mono WAV: the 44-byte canonical header plus the samples, clamped and
    /// scaled from the renderer's float buffer. `AVAudioPlayer` reads this directly — no file on
    /// disk needed.
    private static func wavData(from buffer: AVAudioPCMBuffer) -> Data? {
        guard let floats = buffer.floatChannelData?[0] else { return nil }
        let frameCount = Int(buffer.frameLength)

        var pcm = Data(capacity: frameCount * 2)
        for i in 0..<frameCount {
            let clamped = max(-1, min(1, floats[i]))
            let sample = Int16((clamped * Float(Int16.max)).rounded())
            pcm.append(contentsOf: littleEndianBytes(sample))
        }

        let sampleRateInt = UInt32(sampleRate)
        let bitsPerSample: UInt16 = 16
        let channels: UInt16 = 1
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRateInt * UInt32(blockAlign)
        let dataSize = UInt32(pcm.count)

        var header = Data()
        header.append(contentsOf: Array("RIFF".utf8))
        header.append(contentsOf: littleEndianBytes(UInt32(36) + dataSize))
        header.append(contentsOf: Array("WAVE".utf8))
        header.append(contentsOf: Array("fmt ".utf8))
        header.append(contentsOf: littleEndianBytes(UInt32(16)))          // fmt chunk size
        header.append(contentsOf: littleEndianBytes(UInt16(1)))           // PCM
        header.append(contentsOf: littleEndianBytes(channels))
        header.append(contentsOf: littleEndianBytes(sampleRateInt))
        header.append(contentsOf: littleEndianBytes(byteRate))
        header.append(contentsOf: littleEndianBytes(blockAlign))
        header.append(contentsOf: littleEndianBytes(bitsPerSample))
        header.append(contentsOf: Array("data".utf8))
        header.append(contentsOf: littleEndianBytes(dataSize))

        return header + pcm
    }

    private static func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        withUnsafeBytes(of: value.littleEndian, Array.init)
    }
}
