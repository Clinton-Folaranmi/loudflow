import Foundation

struct WhisperTranscriber: Transcriber {
    private let endpoint = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
    private var apiKey: String? { Keychain.key(for: .whisper) }

    // whisper-1 shuts down on 2027-02-26. It stays only for keys that can't use gpt-transcribe yet.
    private static let model = "gpt-transcribe"
    private static let fallbackModel = "whisper-1"
    private static let uploadLimit = 25_000_000

    func transcribe(_ audioURL: URL, twoTrack: Bool) async throws -> TranscriptionResult {
        guard let key = apiKey else { throw TranscriberError.missingKey }
        guard let audio = try? Data(contentsOf: audioURL) else { throw TranscriberError.decoding }
        guard audio.count < Self.uploadLimit else { throw TranscriberError.tooLarge }

        let fileName = audioURL.lastPathComponent
        do {
            return try await send(audio, fileName: fileName, model: Self.model, key: key)
        } catch TranscriberError.server(let code) where code == 400 || code == 404 {
            return try await send(audio, fileName: fileName, model: Self.fallbackModel, key: key)
        }
    }

    private func send(_ audio: Data, fileName: String, model: String, key: String) async throws -> TranscriptionResult {
        let boundary = "loudflow-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint, timeoutInterval: Self.requestTimeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = Self.multipartBody(boundary: boundary, audio: audio, fileName: fileName, model: model)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw TranscriberError.network
        }
        guard let http = response as? HTTPURLResponse else { throw TranscriberError.network }
        guard (200..<300).contains(http.statusCode) else { throw mapStatus(http.statusCode) }

        guard let decoded = try? JSONDecoder().decode(OpenAITranscription.self, from: data)
        else { throw TranscriberError.decoding }
        return .plain(decoded.text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func validateKey() async -> Bool {
        guard let key = apiKey else { return false }
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private static func multipartBody(boundary: String, audio: Data, fileName: String, model: String) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("response_format", "json")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}

private struct OpenAITranscription: Decodable {
    let text: String
}
