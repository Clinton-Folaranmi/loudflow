import Foundation

// MARK: - Trigger mode

enum TriggerMode: String, CaseIterable, Codable {
    case click, hold, double

    var name: String {
        switch self {
        case .click:  return "Click the widget"
        case .hold:   return "Hold a key"
        case .double: return "Double-tap control"
        }
    }

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
            return "Older clips delete themselves after \(rawValue) days. Transcripts remain."
        }
    }
}

// MARK: - Provider

enum Provider: String, CaseIterable, Codable {
    case deepgram, whisper
    var displayName: String {
        switch self {
        case .deepgram: return "Deepgram"
        case .whisper:  return "OpenAI Whisper"
        }
    }

    var keyURL: URL {
        switch self {
        case .deepgram: return URL(string: "https://console.deepgram.com/signup")!
        case .whisper:  return URL(string: "https://platform.openai.com/api-keys")!
        }
    }
}

// MARK: - Options (the two settings toggles)

struct DictationOptions: Codable, Equatable {
    var insert: Bool = true
    var keep: Bool = true
}

// MARK: - Widget state

enum WidgetState: Equatable {
    case idle
    case recording
    case transcribing
    case queued
    case error(TranscriptionFailure)
}

enum TranscriptionFailure: Equatable {
    case missingKey
    case rejectedKey
    case outOfCredit
    case network

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
