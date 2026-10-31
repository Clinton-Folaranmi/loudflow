import Foundation

struct TimedWord: Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var speaker: Int
}

// Turns provider word timings into speaker turns. Channel 0 is the mic on a two-track recording.
enum TurnBuilder {
    static let echoWindow: TimeInterval = 0.75
    static let flickerWords = 2
    static let flickerSeconds: TimeInterval = 1.2
    static let strayWords = 3
    static let strayShare = 0.1
    static let segmentPause: TimeInterval = 0.8

    static func build(channels: [[TimedWord]], twoTrack: Bool) -> TranscriptionResult {
        var tracks = channels.map { words in
            words.filter { !$0.text.isEmpty }.sorted { $0.start < $1.start }
        }
        let separated = twoTrack && tracks.count > 1
        if separated { tracks[0] = removingEcho(from: tracks[0], heard: tracks[1]) }

        var segments: [Turn] = []
        for (channel, words) in tracks.enumerated() {
            for segment in segmenting(smoothingSpeakers(words)) {
                guard let first = segment.first, let last = segment.last else { continue }
                let speaker = separated ? (channel == 0 ? 0 : 1 + first.speaker) : first.speaker
                segments.append(Turn(speaker: speaker, at: first.start,
                                     text: segment.map(\.text).joined(separator: " "), end: last.end))
            }
        }
        segments.sort { ($0.at, $0.speaker) < ($1.at, $1.speaker) }

        var turns: [Turn] = []
        for segment in segments {
            if var last = turns.last, last.speaker == segment.speaker {
                last.text += " " + segment.text
                last.end = max(last.end ?? last.at, segment.end ?? segment.at)
                turns[turns.count - 1] = last
            } else {
                turns.append(segment)
            }
        }

        let text = turns.map(\.text).joined(separator: " ")
        return TranscriptionResult(text: text, turns: Set(turns.map(\.speaker)).count > 1 ? turns : nil)
    }

    // Without headphones the mic also hears the call, so the far side shows up twice.
    // A mic word that matches a far-side word at about the same moment is that echo.
    static func removingEcho(from mic: [TimedWord], heard far: [TimedWord]) -> [TimedWord] {
        guard !mic.isEmpty, !far.isEmpty else { return mic }
        let farKeys = far.map { normalized($0.text) }

        var echo = [Bool](repeating: false, count: mic.count)
        var low = 0
        for (i, word) in mic.enumerated() {
            let key = normalized(word.text)
            guard !key.isEmpty else { continue }
            while low < far.count, far[low].start < word.start - echoWindow { low += 1 }
            var j = low
            while j < far.count, far[j].start <= word.start + echoWindow {
                if farKeys[j] == key { echo[i] = true; break }
                j += 1
            }
        }

        // A word or two the mic misheard inside an echoed stretch is echo too.
        var i = 0
        while i < mic.count {
            guard !echo[i] else { i += 1; continue }
            var j = i
            while j < mic.count, !echo[j] { j += 1 }
            if i > 0, j < mic.count, j - i <= 2, mic[j].start - mic[i - 1].end < 1.5 {
                for k in i..<j { echo[k] = true }
            }
            i = j
        }

        return zip(mic, echo).compactMap { $1 ? nil : $0 }
    }

    // Diarizers flicker: a word or two of one sentence lands on another voice, or a voice
    // appears for a single word in a recording that only one person spoke in.
    static func smoothingSpeakers(_ words: [TimedWord]) -> [TimedWord] {
        guard words.count > 2 else { return words }
        var out = words

        let runs = runsOfSpeaker(out)
        if runs.count > 2 {
            for i in 1..<(runs.count - 1) {
                let before = runs[i - 1].speaker, after = runs[i + 1].speaker
                guard before == after, runs[i].speaker != before else { continue }
                let range = runs[i].range
                let duration = out[range.upperBound - 1].end - out[range.lowerBound].start
                guard range.count <= flickerWords, duration < flickerSeconds else { continue }
                for k in range { out[k].speaker = before }
            }
        }

        let counts = Dictionary(grouping: out, by: \.speaker).mapValues(\.count)
        let stray = Set(counts.filter { _, count in
            count < strayWords && Double(count) < Double(out.count) * strayShare
        }.keys)
        guard !stray.isEmpty, stray.count < counts.count else { return out }

        var previous: Int?
        for k in out.indices {
            if stray.contains(out[k].speaker) {
                if let previous { out[k].speaker = previous }
            } else {
                previous = out[k].speaker
            }
        }
        if let firstKept = out.first(where: { !stray.contains($0.speaker) })?.speaker {
            for k in out.indices where stray.contains(out[k].speaker) { out[k].speaker = firstKept }
        }
        return out
    }

    // Sentence-sized pieces, so the far side's interjections interleave with a long monologue.
    static func segmenting(_ words: [TimedWord]) -> [[TimedWord]] {
        var segments: [[TimedWord]] = []
        var current: [TimedWord] = []
        for word in words {
            if let last = current.last,
               last.speaker != word.speaker
                || word.start - last.end >= segmentPause
                || last.text.last.map({ ".?!".contains($0) }) == true {
                segments.append(current)
                current = []
            }
            current.append(word)
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    private static func runsOfSpeaker(_ words: [TimedWord]) -> [(speaker: Int, range: Range<Int>)] {
        var runs: [(speaker: Int, range: Range<Int>)] = []
        var start = 0
        for i in 1...words.count where i == words.count || words[i].speaker != words[start].speaker {
            runs.append((words[start].speaker, start..<i))
            start = i
        }
        return runs
    }

    private static func normalized(_ text: String) -> String {
        String(text.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
