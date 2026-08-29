import SwiftUI
import AVFoundation

/// A voice that has turned up in a recording.
///
/// Voices are **global**, not per-clip: `Turn.speaker` holds a voice id, so naming a voice
/// renames every turn it ever spoke, in every clip, at once. Voice 0 is always you — the
/// microphone is its own track, so that one is never a guess — and cannot be renamed or
/// forgotten.
struct Voice: Codable, Equatable, Identifiable {
    var id: Int
    var name: String?
    /// Which row of the design's three-voice palette this voice draws from. Assigned when the
    /// voice is first heard and kept for life, so a voice keeps its colour across recordings.
    var paletteIndex: Int
    /// Two seconds of audio kept from the recording this voice was named in, so you can play
    /// it back and confirm the match. Nil until the voice is named.
    var sampleFileName: String?
    /// A 256-dimensional voice fingerprint, computed on this Mac when the voice was named.
    /// It is what lets a later recording recognise the same person — see `VoiceRecognizer`.
    var embedding: [Float]?

    var isYou: Bool { id == Voice.youID }
    var isNamed: Bool { !(name ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    static let youID = 0

    // MARK: Palette
    //
    // Three voices separated by **hue**, not lightness, each with a text-safe ink that clears
    // 4.5:1 on #FDFBF6 and on a highlighted turn. Fills are for dots and chips only. Marigold
    // is never a speaker — it stays the playhead and selection colour.

    private static let fills: [Color] = [
        Color(hex: 0x7E9A82),   // You
        Color(hex: 0xC2603A),   // second voice
        Color(hex: 0x6E7FA8),   // third / unnamed
    ]
    private static let inks: [Color] = [
        Color(hex: 0x3F5943),
        Color(hex: 0x9E4620),
        Color(hex: 0x465A85),
    ]

    var fill: Color { Voice.fills[min(max(paletteIndex, 0), Voice.fills.count - 1)] }
    var ink: Color { Voice.inks[min(max(paletteIndex, 0), Voice.inks.count - 1)] }

    /// What Settings calls a voice with no name yet.
    var settingsLabel: String { isNamed ? name! : "Unnamed voice" }
}

/// The stored voice profiles, and the audio samples that go with them.
///
/// Persisted to `voices.json` next to the clip index; samples live in `voices/`.
///
/// **How a voice is recognised next time.** A provider's diarization only distinguishes voices
/// *within one recording*, so recognising someone across recordings is done here instead: each
/// named voice keeps an on-device embedding (see `VoiceRecognizer`), and a later recording's
/// speakers are matched against it. When the match isn't confident the voice simply stays
/// unnamed. Typing a name that already belongs to a voice also **merges** the two, which is the
/// manual way to say "this is the same person".
@MainActor
final class VoiceStore: ObservableObject {
    @Published private(set) var voices: [Voice]

    private let indexURL: URL
    private let samplesURL: URL

    init() {
        let root = Persistence.shared.rootURL
        indexURL = root.appendingPathComponent("voices.json")
        samplesURL = root.appendingPathComponent("voices", isDirectory: true)
        try? FileManager.default.createDirectory(at: samplesURL, withIntermediateDirectories: true)

        let loaded = (try? Data(contentsOf: indexURL))
            .flatMap { try? JSONDecoder().decode([Voice].self, from: $0) } ?? []
        voices = loaded.isEmpty ? [Voice(id: Voice.youID, name: "You", paletteIndex: 0)] : loaded
    }

    // MARK: Lookup

    func voice(_ id: Int) -> Voice? { voices.first { $0.id == id } }

    /// Voices worth listing in Settings: you, plus anyone who has actually been heard.
    var listed: [Voice] { voices }

    /// The existing named voice for `name`, if there is one (case- and space-insensitive).
    func named(_ name: String) -> Voice? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return voices.first { ($0.name ?? "").trimmingCharacters(in: .whitespaces).lowercased() == key }
    }

    // MARK: Minting

    /// Mints `count` fresh voices for a new recording's remote speakers and returns their ids.
    /// Palette rows alternate between the two non-you hues, so the second and third voice in a
    /// conversation never look alike.
    func mintVoices(count: Int) -> [Int] {
        var ids: [Int] = []
        var next = (voices.map(\.id).max() ?? Voice.youID) + 1
        var palette = (voices.filter { !$0.isYou }.count % 2) + 1
        for _ in 0..<count {
            voices.append(Voice(id: next, name: nil, paletteIndex: palette))
            ids.append(next)
            next += 1
            palette = palette == 1 ? 2 : 1
        }
        save()
        return ids
    }

    // MARK: Naming

    /// Names a voice. Returns the id the turns should now point at — the same id normally, or
    /// an existing voice's id when the name matches one you have already named (a merge).
    @discardableResult
    func rename(_ id: Int, to rawName: String) -> Int {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, id != Voice.youID else { return id }

        if let existing = named(name), existing.id != id {
            // Same person, met again. Fold this recording's voice into the stored profile and
            // drop the duplicate, so there is only ever one "Ada".
            forget(id, deleteSample: true)
            return existing.id
        }

        guard let idx = voices.firstIndex(where: { $0.id == id }) else { return id }
        voices[idx].name = name
        save()
        return id
    }

    /// Stores a freshly computed voice fingerprint.
    func setEmbedding(_ embedding: [Float], for id: Int) {
        guard let idx = voices.firstIndex(where: { $0.id == id }) else { return }
        voices[idx].embedding = embedding
        save()
    }

    /// Drops a voice's name, its sample, and its fingerprint. You cannot be forgotten.
    func forget(_ id: Int, deleteSample: Bool = true) {
        guard id != Voice.youID, let idx = voices.firstIndex(where: { $0.id == id }) else { return }
        if deleteSample, let file = voices[idx].sampleFileName {
            try? FileManager.default.removeItem(at: sampleURL(file))
        }
        voices[idx].name = nil
        voices[idx].sampleFileName = nil
        voices[idx].embedding = nil
        save()
    }

    /// Removes voices no clip refers to any more, so Settings doesn't fill with strangers.
    func prune(keeping used: Set<Int>) {
        let stale = voices.filter { !$0.isYou && !used.contains($0.id) && !$0.isNamed }
        guard !stale.isEmpty else { return }
        for v in stale where v.sampleFileName != nil {
            try? FileManager.default.removeItem(at: sampleURL(v.sampleFileName!))
        }
        voices.removeAll { v in stale.contains(where: { $0.id == v.id }) }
        save()
    }

    // MARK: Samples

    func sampleURL(_ fileName: String) -> URL { samplesURL.appendingPathComponent(fileName) }

    func sampleURL(for id: Int) -> URL? {
        guard let file = voice(id)?.sampleFileName else { return nil }
        let url = sampleURL(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Keeps two seconds from `source`, starting at `at`, as this voice's sample. Called when a
    /// voice is named, from the recording it was named in.
    func captureSample(for id: Int, from source: URL, at start: TimeInterval) {
        guard id != Voice.youID || voice(id)?.sampleFileName == nil else { return }
        guard FileManager.default.fileExists(atPath: source.path) else { return }

        let fileName = "voice-\(id).m4a"
        let target = sampleURL(fileName)
        try? FileManager.default.removeItem(at: target)

        let asset = AVURLAsset(url: source)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A)
        else { return }
        export.outputURL = target
        export.outputFileType = .m4a
        let from = CMTime(seconds: max(0, start), preferredTimescale: 600)
        export.timeRange = CMTimeRange(start: from, duration: CMTime(seconds: 2, preferredTimescale: 600))
        export.exportAsynchronously { [weak self] in
            guard export.status == .completed else { return }
            Task { @MainActor in
                guard let self, let idx = self.voices.firstIndex(where: { $0.id == id }) else { return }
                self.voices[idx].sampleFileName = fileName
                self.save()
            }
        }
    }

    // MARK: Persistence

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(voices) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
