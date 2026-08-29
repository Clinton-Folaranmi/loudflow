import Foundation

/// Errors a transcription attempt can produce, mapped by `AppModel` onto widget states.
enum TranscriberError: Error {
    case missingKey        // no API key set
    case auth              // key rejected (401/403)
    case credit            // out of credit / quota (402/429-payment)
    case network           // offline / connection failed → queue and retry
    case server(Int)       // other non-2xx
    case decoding          // unexpected response body
}

/// A cloud transcription backend. Deepgram is the shipping default; Whisper is an adapter.
///
/// Contract: return the **raw** transcript text only. No punctuation, capitalization, or
/// cleanup happens here — that single optional transform lives in `AppModel.punctuate`.
protocol Transcriber {
    /// Upload the audio file and return its raw transcript.
    func transcribe(_ audioURL: URL) async throws -> String
    /// Cheap best-effort check that the stored key is accepted.
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

/// Shared helpers for the concrete transcribers.
extension Transcriber {
    /// Maps an HTTP status code to the right `TranscriberError`.
    func mapStatus(_ code: Int) -> TranscriberError {
        switch code {
        case 401, 403: return .auth
        case 402:      return .credit
        case 429:      return .credit   // most providers use 429 for quota exhaustion
        default:       return .server(code)
        }
    }
}
