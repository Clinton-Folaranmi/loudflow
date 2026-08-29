import Foundation

/// One speaker's uninterrupted stretch of a conversation.
///
/// Built by collapsing consecutive same-speaker words from the provider's diarization.
/// `speaker` is a voice id: **0 is always you**, because the microphone is recorded as its own
/// track (see `Recording/`), so that one is never a guess. `at` is seconds from the start of
/// the clip. Speaker and timestamp belong to the audio and are never editable — only `text` is.
struct Turn: Codable, Equatable {
    var speaker: Int
    var at: TimeInterval
    var text: String
}

/// One dictation clip: the audio file on disk plus its (editable) transcript.
///
/// Mirrors the spec's `{ id, time, seconds, sizeMB, text, today }` but stores a real
/// `createdAt` (from which `time` and `today` are derived) and the real audio file name +
/// transcription status the production app needs.
struct Clip: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var seconds: Int
    var sizeBytes: Int64
    var text: String
    /// Speaker turns, when diarization found more than one voice. Single-voice clips leave
    /// this nil and live entirely in `text`; for a conversation, `text` is kept in sync as the
    /// flat transcript so word counts and search don't have to special-case it.
    var turns: [Turn]? = nil
    var audioFileName: String        // relative to the audio dir
    /// The file really has two channels — mic on 0, system audio on 1 — so the provider can be
    /// told to keep them apart instead of guessing who is who.
    var twoTrack: Bool = false
    var audioDeleted: Bool = false   // retention swept the file, transcript kept
    var status: Status = .done

    enum Status: String, Codable {
        case done       // transcript present
        case pending    // recorded, waiting to transcribe (offline queue)
        case failed     // transcription failed (see AppModel.lastFailure)
    }

    init(id: UUID = UUID(),
         createdAt: Date,
         seconds: Int,
         sizeBytes: Int64,
         text: String,
         turns: [Turn]? = nil,
         audioFileName: String,
         twoTrack: Bool = false,
         audioDeleted: Bool = false,
         status: Status = .done) {
        self.id = id
        self.createdAt = createdAt
        self.seconds = seconds
        self.sizeBytes = sizeBytes
        self.text = text
        self.turns = turns
        self.audioFileName = audioFileName
        self.twoTrack = twoTrack
        self.audioDeleted = audioDeleted
        self.status = status
    }

    // MARK: The two kinds of recording

    /// Distinct voice ids in the clip, in first-heard order.
    var speakerIds: [Int] {
        guard let turns else { return [] }
        var seen: [Int] = []
        for t in turns where !seen.contains(t.speaker) { seen.append(t.speaker) }
        return seen
    }

    /// A **conversation** ("meeting") when diarization found more than one voice; otherwise a
    /// **note**. Derived, never stored — there is no meeting mode to switch on.
    var isConversation: Bool { speakerIds.count > 1 }

    var voiceCount: Int { speakerIds.count }

    // MARK: Derived display values

    var sizeMB: Double { Double(sizeBytes) / 1_000_000 }

    /// Was this clip created today (drives the Today tab + its count)?
    var isToday: Bool { Calendar.current.isDateInToday(createdAt) }

    /// "Just now" / "9:41 AM" / "Yesterday, 6:20 PM" / "Aug 3, 2:15 PM".
    var timeLabel: String {
        let cal = Calendar.current
        if Date().timeIntervalSince(createdAt) < 60 { return "Just now" }
        let time = Clip.timeFormatter.string(from: createdAt)
        if cal.isDateInToday(createdAt) { return time }
        if cal.isDateInYesterday(createdAt) { return "Yesterday, \(time)" }
        return "\(Clip.dateFormatter.string(from: createdAt)), \(time)"
    }

    var durationLabel: String { Clip.formatSeconds(seconds) }
    var sizeLabel: String { String(format: "%.2f MB", sizeMB) }
    var wordCount: Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).count
    }

    /// 62-char single-line preview with ellipsis. A conversation is prefixed with whoever
    /// spoke first (`Ada: …`); the truncation still applies to the whole line.
    var preview: String { Self.truncate(text) }

    func preview(voices: [Voice]) -> String {
        guard let first = turns?.first, isConversation else { return preview }
        return Self.truncate("\(speakerLabel(first.speaker, voices: voices)): \(first.text)")
    }

    /// What a transcript calls a speaker: their name if they have one, else `Speaker {n}`
    /// numbered by the order voices are heard in **this** clip — so you are Speaker 1 and the
    /// other side starts at Speaker 2.
    func speakerLabel(_ speaker: Int, voices: [Voice]) -> String {
        if let v = voices.first(where: { $0.id == speaker }), v.isNamed { return v.name! }
        return "Speaker \((speakerIds.firstIndex(of: speaker) ?? speaker) + 1)"
    }

    /// The clipboard form. A meeting copies as `{Speaker}: {text}` blocks separated by blank
    /// lines; a note copies the bare words.
    func copyText(voices: [Voice]) -> String {
        guard isConversation, let turns else { return text }
        return turns
            .map { "\(speakerLabel($0.speaker, voices: voices)): \($0.text)" }
            .joined(separator: "\n\n")
    }

    /// The flat transcript, rebuilt from the turns. Kept in `text` so word counts, previews,
    /// and search never have to know which kind of recording this is.
    var flattenedTurns: String {
        (turns ?? []).map(\.text).joined(separator: " ")
    }

    /// A note's transcript, split into sentences so playback can highlight the one being
    /// spoken. Editing rejoins them, so the split is a display concern only.
    var sentences: [String] {
        var out: [String] = []
        var current = ""
        for ch in text {
            current.append(ch)
            if ".!?".contains(ch) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { out.append(trimmed) }
                current = ""
            }
        }
        let tail = current.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    /// Each sentence's share of the clip, weighted by its length. Real per-word timings would
    /// come from the provider; this is close enough to keep the highlight moving with the
    /// audio on a short note.
    var sentenceRanges: [(start: Double, end: Double)] {
        let list = sentences
        let total = list.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        var acc = 0
        return list.map { s in
            let start = Double(acc) / Double(total) * Double(seconds)
            acc += s.count
            return (start, Double(acc) / Double(total) * Double(seconds))
        }
    }

    private static func truncate(_ s: String) -> String {
        s.count > 62 ? String(s.prefix(62)) + "…" : s
    }

    /// The clip row's second line: `{time} · {n} voices · {size} MB` for a meeting,
    /// `{time} · {size} MB` for a note, and `{time} · transcript only` once retention has
    /// swept the audio.
    var metadataLine: String {
        var parts = [timeLabel]
        if isConversation { parts.append("\(voiceCount) voices") }
        parts.append(audioDeleted ? "transcript only" : sizeLabel)
        return parts.joined(separator: " · ")
    }

    /// True when there's audio but no transcript yet (e.g. it failed / was offline).
    var needsTranscription: Bool { text.isEmpty }

    // MARK: Formatters

    static func formatSeconds(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f
    }()
}
