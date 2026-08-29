import Foundation

/// OpenAI Whisper adapter — a drop-in alternative to Deepgram behind the same protocol.
///
/// Retention caveat (surfaced honestly, per the spec's "don't overclaim" rule): OpenAI's API
/// has **no per-request delete endpoint**. Zero-retention here relies on OpenAI's API data
/// policy — API inputs are not used to train models by default and are retained only briefly
/// for abuse monitoring. Deepgram's `mip_opt_out` is a more literal fit for "zero-retention",
/// which is why Deepgram is the default.
struct WhisperTranscriber: Transcriber {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private var apiKey: String? { Keychain.key(for: .whisper) }

    func transcribe(_ audioURL: URL, twoTrack: Bool) async throws -> TranscriptionResult {
        guard let key = apiKey else { throw TranscriberError.missingKey }
        guard let audio = try? Data(contentsOf: audioURL) else { throw TranscriberError.decoding }

        let boundary = "loudflow-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.multipartBody(boundary: boundary, audio: audio,
                                          fileName: audioURL.lastPathComponent)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw TranscriberError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TranscriberError.network }
        guard (200..<300).contains(http.statusCode) else { throw mapStatus(http.statusCode) }

        // response_format=text → the body is the transcript, already punctuated by the model.
        guard let text = String(data: data, encoding: .utf8) else { throw TranscriberError.decoding }
        return .plain(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func validateKey() async -> Bool {
        guard let key = apiKey else { return false }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private static func multipartBody(boundary: String, audio: Data, fileName: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", "whisper-1")
        field("response_format", "text")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
