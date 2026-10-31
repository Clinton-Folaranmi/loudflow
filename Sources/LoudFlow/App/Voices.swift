import SwiftUI
import AVFoundation

// Turn.speaker stores a global voice ID. ID 0 is reserved for the mic user.
struct Voice: Codable, Equatable, Identifiable {
    var id: Int
    var name: String?
    var paletteIndex: Int
    var sampleFileName: String?
    // Average of every confirmed sample of this voice; embeddingCount says how many.
    var embedding: [Float]?
    var embeddingCount: Int?

    var isYou: Bool { id == Voice.youID }
    var isNamed: Bool { !(name ?? "").trimmingCharacters(in: .whitespaces).isEmpty }

    static let youID = 0

    private static let fills: [Color] = [
        Color(hex: 0x7E9A82),
        Color(hex: 0xC2603A),
        Color(hex: 0x6E7FA8),
    ]
    private static let inks: [Color] = [
        Color(hex: 0x3F5943),
        Color(hex: 0x9E4620),
        Color(hex: 0x465A85),
    ]

    var fill: Color { Voice.fills[min(max(paletteIndex, 0), Voice.fills.count - 1)] }
    var ink: Color { Voice.inks[min(max(paletteIndex, 0), Voice.inks.count - 1)] }

    var settingsLabel: String { isNamed ? name! : "Unnamed voice" }
}

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

    func voice(_ id: Int) -> Voice? { voices.first { $0.id == id } }

    var listed: [Voice] { voices }

    func named(_ name: String) -> Voice? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return voices.first {
            !$0.isYou && ($0.name ?? "").trimmingCharacters(in: .whitespaces).lowercased() == key
        }
    }

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

    @discardableResult
    func rename(_ id: Int, to rawName: String) -> Int {
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return id }

        if id != Voice.youID, let existing = named(name), existing.id != id {
            // Reuse the existing profile so one person keeps one ID across clips.
            forget(id, deleteSample: true)
            return existing.id
        }

        guard let idx = voices.firstIndex(where: { $0.id == id }) else { return id }
        voices[idx].name = name
        save()
        return id
    }

    // Past this, new samples still count but can't swamp a settled profile.
    private static let profileMemory = 20

    func learn(_ embedding: [Float], for id: Int) {
        guard let idx = voices.firstIndex(where: { $0.id == id }) else { return }
        let fresh = VoiceRecognizer.normalized(embedding)
        let count = voices[idx].embeddingCount ?? 1
        if let known = voices[idx].embedding, known.count == fresh.count {
            let weight = Float(min(count, Self.profileMemory))
            voices[idx].embedding = VoiceRecognizer.normalized(
                zip(known, fresh).map { ($0 * weight + $1) / (weight + 1) })
            voices[idx].embeddingCount = count + 1
        } else {
            voices[idx].embedding = fresh
            voices[idx].embeddingCount = 1
        }
        save()
    }

    func forget(_ id: Int, deleteSample: Bool = true) {
        guard id != Voice.youID, let idx = voices.firstIndex(where: { $0.id == id }) else { return }
        if deleteSample, let file = voices[idx].sampleFileName {
            try? FileManager.default.removeItem(at: sampleURL(file))
        }
        voices[idx].name = nil
        voices[idx].sampleFileName = nil
        voices[idx].embedding = nil
        voices[idx].embeddingCount = nil
        save()
    }

    func prune(keeping used: Set<Int>) {
        let stale = voices.filter { !$0.isYou && !used.contains($0.id) && !$0.isNamed }
        guard !stale.isEmpty else { return }
        for v in stale where v.sampleFileName != nil {
            try? FileManager.default.removeItem(at: sampleURL(v.sampleFileName!))
        }
        voices.removeAll { v in stale.contains(where: { $0.id == v.id }) }
        save()
    }

    func sampleURL(_ fileName: String) -> URL { samplesURL.appendingPathComponent(fileName) }

    func sampleURL(for id: Int) -> URL? {
        guard let file = voice(id)?.sampleFileName else { return nil }
        let url = sampleURL(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

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

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(voices) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
