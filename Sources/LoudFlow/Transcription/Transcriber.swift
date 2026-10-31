import Foundation

enum TranscriberError: Error {
    case missingKey
    case auth
    case credit
    case network
    case server(Int)
    case decoding
}

struct TranscriptionResult {
    var text: String
    var turns: [Turn]?

    static func plain(_ text: String) -> TranscriptionResult { .init(text: text, turns: nil) }
}

protocol Transcriber {
    func transcribe(_ audioURL: URL, twoTrack: Bool, vocabulary: [String]) async throws -> TranscriptionResult
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
    func mapStatus(_ code: Int) -> TranscriberError {
        switch code {
        case 401, 403: return .auth
        case 402:      return .credit
        case 429:      return .credit
        default:       return .server(code)
        }
    }
}
