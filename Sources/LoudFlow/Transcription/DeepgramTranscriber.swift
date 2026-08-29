import Foundation

/// Deepgram pre-recorded transcription (the shipping default).
///
/// Privacy posture (matches the spec's "zero-retention" requirement):
///   • `mip_opt_out=true` opts the audio out of Deepgram's Model Improvement Program, so it
///     is not retained to train models. (For the strongest guarantee, also disable data
///     logging at the Deepgram project level.)
///   • `punctuate=false` and `smart_format=false` — we want the **raw** transcript. The one
///     optional punctuation pass happens locally in `AppModel`, never on the provider.
struct DeepgramTranscriber: Transcriber {
    private let endpoint = URL(string:
        "https://api.deepgram.com/v1/listen?model=nova-2&punctuate=false&smart_format=false&mip_opt_out=true")!

    private var apiKey: String? { Keychain.key(for: .deepgram) }

    func transcribe(_ audioURL: URL) async throws -> String {
        guard let key = apiKey else { throw TranscriberError.missingKey }
        guard let audio = try? Data(contentsOf: audioURL) else { throw TranscriberError.decoding }

        var req = URLRequest(url: endpoint)
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
              let transcript = decoded.results?.channels?.first?.alternatives?.first?.transcript
        else { throw TranscriberError.decoding }

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validateKey() async -> Bool {
        guard let key = apiKey else { return false }
        var req = URLRequest(url: URL(string: "https://api.deepgram.com/v1/projects")!)
        req.setValue("Token \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }
}

// MARK: - Response shape (only the fields we read)

private struct DeepgramResponse: Decodable {
    struct Results: Decodable { let channels: [Channel]? }
    struct Channel: Decodable { let alternatives: [Alternative]? }
    struct Alternative: Decodable { let transcript: String? }
    let results: Results?
}
