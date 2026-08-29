import Foundation

/// Local, on-disk storage: `~/Library/Application Support/LoudFlow/`
///   • `clips.json`   — the transcript index (Codable `[Clip]`)
///   • `audio/*.m4a`  — the recordings
///
/// Nothing here is uploaded. (Transcription uploads a copy of the audio to the provider at
/// record time; that is handled in `Transcription/`, not here.)
final class Persistence {
    static let shared = Persistence()

    let rootURL: URL
    let audioURL: URL
    private let indexURL: URL

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LoudFlow", isDirectory: true)
        rootURL = base
        audioURL = base.appendingPathComponent("audio", isDirectory: true)
        indexURL = base.appendingPathComponent("clips.json")
        try? FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
    }

    // MARK: Clip index

    func loadClips() -> [Clip] {
        guard let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Clip].self, from: data)) ?? []
    }

    func saveClips(_ clips: [Clip]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(clips) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    // MARK: Audio files

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

    /// Total bytes of stored audio (for the disk meter).
    func totalAudioBytes() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: audioURL, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { sum, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return sum + Int64(size)
        }
    }
}
