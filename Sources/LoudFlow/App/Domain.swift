import Foundation

// MARK: - Trigger mode

/// How recording starts. Exactly one is active; the widget's label and keycap reflect it.
enum TriggerMode: String, CaseIterable, Codable {
    case click, hold, double

    var name: String {
        switch self {
        case .click:  return "Click the widget"
        case .hold:   return "Hold a key"
        case .double: return "Double-tap control"
        }
    }

    /// The keycap combo shown in the widget / settings.
    var combo: String {
        switch self {
        case .click:  return "no keys"
        case .hold:   return "⌥ Space"
        case .double: return "⌃⌃"
        }
    }

    var desc: String {
        switch self {
        case .click:  return "Nothing to remember. It sits there quietly."
        case .hold:   return "Can't record by accident. Talk while you hold."
        case .double: return "Hands free, tap again to stop."
        }
    }

    /// Solar icon name (see `Solar`).
    var iconName: String {
        switch self {
        case .click:  return Solar.cursor
        case .hold:   return Solar.keyboard
        case .double: return Solar.handStars
        }
    }

    var widgetLabel: String { self == .hold ? "Hold to record" : "Record" }
    var stopHint: String { self == .hold ? "let go to stop" : "tap to stop" }
}

// MARK: - Retention

enum Retention: String, CaseIterable, Codable {
    case sevenDays = "7"
    case thirtyDays = "30"
    case forever

    var label: String {
        switch self {
        case .sevenDays:  return "7 days"
        case .thirtyDays: return "30 days"
        case .forever:    return "Forever"
        }
    }

    var note: String {
        switch self {
        case .sevenDays:  return "Tidiest option"
        case .thirtyDays: return "Sensible middle"
        case .forever:    return "Until you delete them"
        }
    }

    /// Days after which audio is swept; nil = never.
    var days: Int? {
        switch self {
        case .sevenDays:  return 7
        case .thirtyDays: return 30
        case .forever:    return nil
        }
    }

    var settingsNote: String {
        switch self {
        case .forever:
            return "Nothing gets deleted on its own. Watch the disk meter."
        default:
            return "Older clips delete themselves after \(rawValue) days. Transcripts stay."
        }
    }
}

// MARK: - Provider

/// Cloud transcription provider. Deepgram is the shipping default; Whisper slots in behind
/// the same `Transcriber` protocol.
enum Provider: String, CaseIterable, Codable {
    case deepgram, whisper
    var displayName: String {
        switch self {
        case .deepgram: return "Deepgram"
        case .whisper:  return "OpenAI Whisper"
        }
    }
}

// MARK: - Options (the three settings toggles)

struct DictationOptions: Codable, Equatable {
    /// Type the transcript into the frontmost field; off = clipboard only.
    var insert: Bool = true
    /// Keep the audio, not just the text.
    var keep: Bool = true
    /// Add punctuation (capitalize first char, append a full stop). No rephrasing, ever.
    var punct: Bool = true
}

// MARK: - Widget state

/// What the floating widget is currently showing. The error/queued cases are net-new
/// (the spec had no failure state) and were added with the app owner's sign-off.
enum WidgetState: Equatable {
    case idle
    case recording
    case transcribing
    case queued              // saved locally, waiting for the network
    case error(TranscriptionFailure)
}

/// The distinct transcription failures the widget surfaces, each with its own copy + action.
enum TranscriptionFailure: Equatable {
    case missingKey          // no key set yet
    case rejectedKey         // provider returned 401/403
    case outOfCredit         // provider returned payment/quota error
    case network             // treated as "queued", not a hard error, but kept for completeness

    var message: String {
        switch self {
        case .missingKey:  return "No transcription key yet."
        case .rejectedKey: return "That key was rejected."
        case .outOfCredit: return "Transcription account is out of credit."
        case .network:     return "No network — saved it to try later."
        }
    }

    var action: String {
        switch self {
        case .missingKey:  return "Add one"
        case .rejectedKey: return "Fix it"
        case .outOfCredit: return "Open settings"
        case .network:     return ""
        }
    }
}
