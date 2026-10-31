import Foundation
import AVFoundation

@MainActor
enum Earcons {

    static func recordStart() { play(.recordStart, [Tone(hz: 784, ms: 70, gain: 0.30, delayMs: 0)]) }

    static func recordStop() { play(.recordStop, [Tone(hz: 523, ms: 70, gain: 0.30, delayMs: 0)]) }

    static func transcriptLanded() {
        play(.transcriptLanded, [
            Tone(hz: 1046, ms: 50, gain: 0.22, delayMs: 0),
            Tone(hz: 1318, ms: 80, gain: 0.26, delayMs: 55),
        ])
    }

    private enum Sound { case recordStart, recordStop, transcriptLanded }

    // AVAudioEngine lost its player node when recording changed the audio device.
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

    private struct Tone {
        let hz: Double
        let ms: Double
        let gain: Double
        let delayMs: Double
    }

    private static let sampleRate: Double = 44_100
    private static let attack: Double = 0.004

    private static func render(_ tones: [Tone]) -> AVAudioPCMBuffer? {
        let total = tones.map { ($0.delayMs + $0.ms) / 1000 }.max() ?? 0
        let frames = AVAudioFrameCount((total + 0.02) * sampleRate)
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

                let tri = 4 * abs(phase - 0.5) - 1
                phase += step
                if phase >= 1 { phase -= 1 }

                lp += a * (tri - lp)

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
        header.append(contentsOf: littleEndianBytes(UInt32(16)))
        header.append(contentsOf: littleEndianBytes(UInt16(1)))
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
