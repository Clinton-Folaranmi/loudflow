import Foundation

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
    var audioFileName: String        // relative to the audio dir
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
         audioFileName: String,
         audioDeleted: Bool = false,
         status: Status = .done) {
        self.id = id
        self.createdAt = createdAt
        self.seconds = seconds
        self.sizeBytes = sizeBytes
        self.text = text
        self.audioFileName = audioFileName
        self.audioDeleted = audioDeleted
        self.status = status
    }

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

    /// 62-char single-line preview with ellipsis, per the spec.
    var preview: String {
        text.count > 62 ? String(text.prefix(62)) + "…" : text
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
