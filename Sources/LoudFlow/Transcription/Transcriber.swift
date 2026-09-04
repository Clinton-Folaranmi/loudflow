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

/// What a provider gives back.
///
/// `turns` is nil when only one voice was heard — that clip is a note and lives entirely in
/// `text`. When there are two or more, `speaker` holds a **local** index: 0 is always the
/// microphone track (you), and the other side starts at 1. `AppModel` maps those onto stored
/// voice ids before the clip is saved.
struct TranscriptionResult {
    var text: String
    var turns: [Turn]?

    static func plain(_ text: String) -> TranscriptionResult { .init(text: text, turns: nil) }
}

/// A cloud transcription backend. Deepgram is the shipping default; Whisper is an adapter.
///
/// Contract: return the provider's own **formatted** output — punctuation, paragraph breaks at
/// natural pauses, and number/date/currency formatting are the model's, not a rewrite, so they
/// are always on and there is nothing to opt out of. What never happens, here or anywhere else
/// in the app, is **rewording**: no tone presets, no LLM cleanup.
protocol Transcriber {
    /// Upload the audio file and return its transcript.
    ///
    /// `twoTrack` says the file has the microphone on channel 0 and system audio on channel 1,
    /// so the provider can be asked to keep the channels apart instead of guessing who is who.
    ///
    /// `vocabulary` is names, jargon and spellings to bias decoding toward — see
    /// `AppModel.effectiveVocabulary`, which is what's actually passed in (the user's own list
    /// plus every named voice, so naming someone helps their own transcript for free). Each
    /// adapter maps it onto whatever hint mechanism its provider offers; an empty list is a
    /// no-op either way.
    func transcribe(_ audioURL: URL, twoTrack: Bool, vocabulary: [String]) async throws -> TranscriptionResult
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
