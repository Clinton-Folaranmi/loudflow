import Foundation

/// Non-secret user settings, persisted in UserDefaults. (The API key is the one thing that
/// does NOT live here — it's in the Keychain; see `Keychain`.)
enum Preferences {
    private static let d = UserDefaults.standard

    private enum Key {
        static let trigger = "trigger"
        static let retention = "retention"
        static let optionInsert = "opt.insert"
        static let optionKeep = "opt.keep"
        static let provider = "provider"
        static let onboarded = "onboarded"
        static let wordsToday = "wordsToday"
        static let wordsTodayDay = "wordsTodayDay"   // yyyy-ddd to reset the counter daily
        static let vocabulary = "vocabulary"
    }

    static var trigger: TriggerMode {
        get { TriggerMode(rawValue: d.string(forKey: Key.trigger) ?? "") ?? .click }
        set { d.set(newValue.rawValue, forKey: Key.trigger) }
    }

    static var retention: Retention {
        get { Retention(rawValue: d.string(forKey: Key.retention) ?? "") ?? .thirtyDays }
        set { d.set(newValue.rawValue, forKey: Key.retention) }
    }

    static var options: DictationOptions {
        get {
            DictationOptions(
                insert: d.object(forKey: Key.optionInsert) as? Bool ?? true,
                keep: d.object(forKey: Key.optionKeep) as? Bool ?? true
            )
        }
        set {
            d.set(newValue.insert, forKey: Key.optionInsert)
            d.set(newValue.keep, forKey: Key.optionKeep)
        }
    }

    static var provider: Provider {
        get { Provider(rawValue: d.string(forKey: Key.provider) ?? "") ?? .deepgram }
        set { d.set(newValue.rawValue, forKey: Key.provider) }
    }

    /// What the greeting calls you. nil = fall back to the macOS account first name.
    static var displayName: String? {
        get {
            let s = d.string(forKey: "displayName")?.trimmingCharacters(in: .whitespaces)
            return (s?.isEmpty ?? true) ? nil : s
        }
        set {
            if let v = newValue, !v.trimmingCharacters(in: .whitespaces).isEmpty {
                d.set(v, forKey: "displayName")
            } else {
                d.removeObject(forKey: "displayName")
            }
        }
    }

    static var onboarded: Bool {
        get { d.bool(forKey: Key.onboarded) }
        set { d.set(newValue, forKey: Key.onboarded) }
    }

    /// Words dictated today, reset when the day rolls over.
    static var wordsToday: Int {
        get {
            if d.string(forKey: Key.wordsTodayDay) != Self.todayStamp { return 0 }
            return d.integer(forKey: Key.wordsToday)
        }
        set {
            d.set(Self.todayStamp, forKey: Key.wordsTodayDay)
            d.set(newValue, forKey: Key.wordsToday)
        }
    }

    private static let dayStampFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static var todayStamp: String { dayStampFormatter.string(from: Date()) }

    /// Names, jargon and spellings to bias transcription toward. Sent to whichever provider is
    /// active — see `Transcriber.transcribe(_:twoTrack:vocabulary:)`. Order is preserved so the
    /// Settings list doesn't reshuffle as you add to it.
    static var vocabulary: [String] {
        get { d.stringArray(forKey: Key.vocabulary) ?? [] }
        set { d.set(newValue, forKey: Key.vocabulary) }
    }

    /// The floating widget's saved bottom-left origin (screen coords), or nil to use the
    /// default bottom-right position.
    static var widgetOrigin: CGPoint? {
        get {
            guard d.object(forKey: "widget.x") != nil else { return nil }
            return CGPoint(x: d.double(forKey: "widget.x"), y: d.double(forKey: "widget.y"))
        }
        set {
            if let p = newValue {
                d.set(p.x, forKey: "widget.x")
                d.set(p.y, forKey: "widget.y")
            } else {
                d.removeObject(forKey: "widget.x")
                d.removeObject(forKey: "widget.y")
            }
        }
    }
}
