import Foundation

struct Clip: Identifiable, Codable, Equatable {
    let id: UUID
    var createdAt: Date
    var seconds: Int
    var sizeBytes: Int64
    var text: String
    var title: String? = nil

    // Single-voice clips keep plain text; nil turns also supports older saved clips.
    var turns: [Turn]? = nil
    var audioFileName: String
    var twoTrack: Bool = false
    // Another app was playing during the recording, but the call track stayed silent.
    var callAudioMissed: Bool? = nil
    var audioDeleted: Bool = false
    var status: Status = .done

    enum Status: String, Codable {
        case done
        case pending
        case failed
    }

    init(id: UUID = UUID(),
         createdAt: Date,
         seconds: Int,
         sizeBytes: Int64,
         text: String,
         title: String? = nil,
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
        self.title = title
        self.turns = turns
        self.audioFileName = audioFileName
        self.twoTrack = twoTrack
        self.audioDeleted = audioDeleted
        self.status = status
    }

    var speakerIds: [Int] {
        guard let turns else { return [] }
        var seen: [Int] = []
        for t in turns where !seen.contains(t.speaker) { seen.append(t.speaker) }
        return seen
    }

    var isConversation: Bool { speakerIds.count > 1 }

    var voiceCount: Int { speakerIds.count }

    var sizeMB: Double { Double(sizeBytes) / 1_000_000 }

    var isToday: Bool { Calendar.current.isDateInToday(createdAt) }

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

    var preview: String { Self.truncate(text) }

    func preview(voices: [Voice]) -> String {
        guard let first = turns?.first, isConversation else { return preview }
        return Self.truncate("\(speakerLabel(first.speaker, voices: voices)): \(first.text)")
    }

    func speakerLabel(_ speaker: Int, voices: [Voice]) -> String {
        if let v = voices.first(where: { $0.id == speaker }), v.isNamed { return v.name! }
        return "Speaker \((speakerIds.firstIndex(of: speaker) ?? speaker) + 1)"
    }

    func copyText(voices: [Voice]) -> String {
        guard isConversation, let turns else { return text }
        return turns
            .map { "\(speakerLabel($0.speaker, voices: voices)): \($0.text)" }
            .joined(separator: "\n\n")
    }

    var flattenedTurns: String {
        (turns ?? []).map(\.text).joined(separator: " ")
    }

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

    var metadataLine: String {
        var parts = [timeLabel]
        if isConversation { parts.append("\(voiceCount) voices") }
        parts.append(audioDeleted ? "transcript only" : sizeLabel)
        return parts.joined(separator: " · ")
    }

    var needsTranscription: Bool { text.isEmpty }

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
