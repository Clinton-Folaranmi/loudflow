import Foundation

/// Deepgram pre-recorded transcription (the shipping default).
///
/// Privacy posture (matches the spec's "zero-retention" requirement):
///   • `mip_opt_out=true` opts the audio out of Deepgram's Model Improvement Program, so it
///     is not retained to train models. (For the strongest guarantee, also disable data
///     logging at the Deepgram project level.)
///
/// Formatting posture: `punctuate`, `paragraphs`, and `smart_format` are **on**. That output is
/// the ASR model's own — punctuation, breaks at natural pauses, and readable numbers, dates and
/// currency — not a rewrite, so there is nothing for the user to opt out of. Rewording is what
/// the app refuses, and no request here asks for any.
///
/// `diarize=true` returns a speaker index per word, which becomes the clip's turns. When the
/// recording has two tracks (mic on channel 0, system audio on channel 1) `multichannel=true`
/// is added as well, so channel 0 is known to be you and diarization only has to split the
/// remote side.
struct DeepgramTranscriber: Transcriber {
    private static let base = "https://api.deepgram.com/v1/listen"
    private static let common =
        "model=nova-2&punctuate=true&paragraphs=true&smart_format=true&diarize=true&mip_opt_out=true"

    private func endpoint(twoTrack: Bool) -> URL {
        URL(string: "\(Self.base)?\(Self.common)\(twoTrack ? "&multichannel=true" : "")")!
    }

    private var apiKey: String? { Keychain.key(for: .deepgram) }

    func transcribe(_ audioURL: URL, twoTrack: Bool) async throws -> TranscriptionResult {
        guard let key = apiKey else { throw TranscriberError.missingKey }
        guard let audio = try? Data(contentsOf: audioURL) else { throw TranscriberError.decoding }

        var req = URLRequest(url: endpoint(twoTrack: twoTrack))
        req.httpMethod = "POST"
        req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.upload(for: req, from: audio)
        } catch {
            throw TranscriberError.network
        }

        guard let http = response as? HTTPURLResponse else { throw TranscriberError.network }
        guard (200..<300).contains(http.statusCode) else { throw mapStatus(http.statusCode) }

        guard let decoded = try? JSONDecoder().decode(DeepgramResponse.self, from: data),
              let channels = decoded.results?.channels, !channels.isEmpty
        else { throw TranscriberError.decoding }

        return Self.result(from: channels, twoTrack: twoTrack)
    }

    func validateKey() async -> Bool {
        guard let key = apiKey else { return false }
        var req = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
        req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    // MARK: - Words → turns

    /// Collapses consecutive words by the same speaker into turns, in time order.
    ///
    /// With two tracks, the channel decides the speaker and diarization only subdivides the
    /// remote side: channel 0 is you (local index 0), channel 1's diarized speakers start at 1.
    /// With one track, the diarized index is used directly.
    static func result(from channels: [DeepgramResponse.Channel], twoTrack: Bool) -> TranscriptionResult {
        struct Word { let speaker: Int; let at: TimeInterval; let text: String }

        var words: [Word] = []
        for (channelIndex, channel) in channels.enumerated() {
            guard let alt = channel.alternatives?.first else { continue }
            for w in alt.words ?? [] {
                let local: Int
                if twoTrack, channels.count > 1 {
                    local = channelIndex == 0 ? 0 : 1 + (w.speaker ?? 0)
                } else {
                    local = w.speaker ?? 0
                }
                words.append(Word(speaker: local,
                                  at: w.start ?? 0,
                                  text: w.punctuated_word ?? w.word ?? ""))
            }
        }
        words.sort { $0.at < $1.at }

        // No per-word detail (or no diarization) — fall back to the flat transcript.
        guard !words.isEmpty else {
            let flat = channels
                .compactMap { $0.alternatives?.first?.transcript }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .plain(flat)
        }

        var turns: [Turn] = []
        for w in words where !w.text.isEmpty {
            if var last = turns.last, last.speaker == w.speaker {
                last.text += " " + w.text
                turns[turns.count - 1] = last
            } else {
                turns.append(Turn(speaker: w.speaker, at: w.at, text: w.text))
            }
        }

        let flat = turns.map(\.text).joined(separator: " ")
        // One voice is a note, not a conversation — it lives in `text` alone.
        let distinct = Set(turns.map(\.speaker))
        return TranscriptionResult(text: flat, turns: distinct.count > 1 ? turns : nil)
    }
}

// MARK: - Response shape (only the fields we read)

struct DeepgramResponse: Decodable {
    struct Results: Decodable { let channels: [Channel]? }
    struct Channel: Decodable { let alternatives: [Alternative]? }
    struct Alternative: Decodable {
        let transcript: String?
        let words: [Word]?
    }
    struct Word: Decodable {
        let word: String?
        let punctuated_word: String?
        let start: TimeInterval?
        let speaker: Int?
    }
    let results: Results?
}
