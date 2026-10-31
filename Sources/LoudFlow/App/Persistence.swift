import Foundation

final class Persistence {
    static let shared = Persistence()

    let rootURL: URL
    let audioURL: URL
    private let indexURL: URL
    private let backupURL: URL

    // Saves run off the main thread; a burst of edits becomes one write of the latest list.
    private let writer = DispatchQueue(label: "com.loudflow.persistence", qos: .utility)
    private let pendingLock = NSLock()
    private var pendingClips: [Clip]?
    private var writeScheduled = false

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LoudFlow", isDirectory: true)
        rootURL = base
        audioURL = base.appendingPathComponent("audio", isDirectory: true)
        indexURL = base.appendingPathComponent("clips.json")
        backupURL = base.appendingPathComponent("clips.backup.json")
        try? FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
    }

    func loadClips() -> [Clip] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let clips = try? decoder.decode([Clip].self, from: data) else {
            // An unreadable library would otherwise be overwritten by the next save.
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = rootURL.appendingPathComponent("clips.unreadable-\(stamp).json")
            try? FileManager.default.moveItem(at: indexURL, to: aside)
            return []
        }
        // The library as it was at launch, in case something goes wrong during this run.
        try? FileManager.default.removeItem(at: backupURL)
        try? FileManager.default.copyItem(at: indexURL, to: backupURL)
        return clips
    }

    func saveClips(_ clips: [Clip]) {
        pendingLock.lock()
        pendingClips = clips
        let schedule = !writeScheduled
        writeScheduled = true
        pendingLock.unlock()
        guard schedule else { return }
        writer.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.writePending() }
    }

    // Called on quit so the last edit isn't lost in the save delay.
    func flush() {
        writer.sync { writePending() }
    }

    private func writePending() {
        pendingLock.lock()
        let clips = pendingClips
        pendingClips = nil
        writeScheduled = false
        pendingLock.unlock()
        guard let clips else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(clips) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    struct SavedSuggestions: Codable {
        var suggestions: [String: [String: Int]] = [:]
        var rejected: [String] = []
    }

    private var suggestionsURL: URL { rootURL.appendingPathComponent("suggestions.json") }

    func loadSuggestions() -> SavedSuggestions {
        (try? Data(contentsOf: suggestionsURL))
            .flatMap { try? JSONDecoder().decode(SavedSuggestions.self, from: $0) } ?? SavedSuggestions()
    }

    func saveSuggestions(_ saved: SavedSuggestions) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(saved) else { return }
        try? data.write(to: suggestionsURL, options: .atomic)
    }

    func newAudioURL() -> (url: URL, fileName: String) {
        let name = "\(UUID().uuidString).m4a"
        return (audioURL.appendingPathComponent(name), name)
    }

    func url(forAudio fileName: String) -> URL {
        audioURL.appendingPathComponent(fileName)
    }

    func deleteAudio(fileName: String) {
        try? FileManager.default.removeItem(at: url(forAudio: fileName))
    }

    func fileSize(fileName: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url(forAudio: fileName).path)
        return (attrs?[.size] as? Int64) ?? 0
    }

    func availableBytes() -> Int64 {
        let values = try? audioURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    // A recording that never finished (a crash or force quit) leaves its raw tracks behind.
    func removeScratchRecordings() {
        let files = (try? FileManager.default.contentsOfDirectory(at: audioURL, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasSuffix(".mic.caf") || file.lastPathComponent.hasSuffix(".sys.caf") {
            try? FileManager.default.removeItem(at: file)
        }
    }

    func totalAudioBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: audioURL, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }
}
