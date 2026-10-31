import Foundation

enum TranscriberError: Error {
    case missingKey
    case auth
    case credit
    case network
    case server(Int)
    case decoding
    case tooLarge
}

struct TranscriptionResult {
    var text: String
    var turns: [Turn]?

    static func plain(_ text: String) -> TranscriptionResult { .init(text: text, turns: nil) }
}

protocol Transcriber {
    func transcribe(_ audioURL: URL, twoTrack: Bool) async throws -> TranscriptionResult
    func validateKey() async -> Bool
}

enum TranscriberFactory {
    static func make(provider: Provider) -> Transcriber {
        switch provider {
        case .deepgram: return DeepgramTranscriber()
        case .whisper:  return WhisperTranscriber()
        }
    }
}

extension Transcriber {
    // Long meetings upload for a while and the provider then works through the whole file.
    static var requestTimeout: TimeInterval { 600 }

    func mapStatus(_ code: Int) -> TranscriberError {
        switch code {
        case 401, 403: return .auth
        case 402:      return .credit
        case 413:      return .tooLarge
        case 429:      return .credit
        default:       return .server(code)
        }
    }
}
