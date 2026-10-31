import XCTest

final class TurnBuilderTests: XCTestCase {

    // Words 0.3 s long with a 0.05 s gap, starting at `from`.
    private func say(_ text: String, from start: TimeInterval, speaker: Int) -> [TimedWord] {
        var at = start
        return text.split(separator: " ").map { word in
            defer { at += 0.35 }
            return TimedWord(text: String(word), start: at, end: at + 0.3, speaker: speaker)
        }
    }

    func testFlickerInsideASentenceIsAbsorbed() {
        var words = say("I think we should ship the build on Friday morning.", from: 0, speaker: 0)
        words[4].speaker = 1
        let result = TurnBuilder.build(channels: [words], twoTrack: false)
        XCTAssertNil(result.turns)
        XCTAssertEqual(result.text, "I think we should ship the build on Friday morning.")
    }

    func testRealMonoConversationKeepsItsTurns() {
        let words = say("Can you send me the deck before the meeting?", from: 0, speaker: 0)
            + say("Sure, I'll send it over in an hour or so.", from: 4, speaker: 1)
            + say("Great, thanks.", from: 8.5, speaker: 0)
        let result = TurnBuilder.build(channels: [words], twoTrack: false)
        XCTAssertEqual(result.turns?.map(\.speaker), [0, 1, 0])
    }

    func testTurnEndIsTheLastWordsEnd() {
        let first = say("Can you send me the deck before the meeting?", from: 0, speaker: 0)
        let words = first
            + say("Sure, I'll send it over in an hour or so.", from: 4, speaker: 1)
            + say("Great, thanks.", from: 8.5, speaker: 0)
        let result = TurnBuilder.build(channels: [words], twoTrack: false)
        XCTAssertEqual(result.turns?.first?.end ?? -1, first.last!.end, accuracy: 0.001)
    }

    func testOneWordStrayVoiceInADictationIsMerged() {
        var words = say("Remind me to call the dentist tomorrow and also pick up groceries on the way home tonight please okay thanks.", from: 0, speaker: 0)
        words[words.count - 1].speaker = 1
        XCTAssertNil(TurnBuilder.build(channels: [words], twoTrack: false).turns)
    }

    func testShortGenuineReplySurvivesInAThreePersonMeeting() {
        let words = say("What do you both think about the pricing page?", from: 0, speaker: 0)
            + say("I like it.", from: 4, speaker: 1)
            + say("I think the headline needs work but the table is good.", from: 6, speaker: 2)
        let result = TurnBuilder.build(channels: [words], twoTrack: false)
        XCTAssertEqual(result.turns?.map(\.speaker), [0, 1, 2])
    }

    func testEchoOfTheFarSideIsRemovedFromTheMic() {
        let far = say("Hi Clinton, how was the launch yesterday?", from: 1.0, speaker: 0)
        let mic = say("Hi Clinton, how was the launch yesterday?", from: 1.12, speaker: 0)
            + say("It went really well, thanks for asking.", from: 5.0, speaker: 0)
        let result = TurnBuilder.build(channels: [mic, far], twoTrack: true)
        XCTAssertEqual(result.turns?.map(\.speaker), [1, 0])
        XCTAssertEqual(result.text, "Hi Clinton, how was the launch yesterday? It went really well, thanks for asking.")
    }

    func testMisheardWordInsideAnEchoIsDroppedToo() {
        let far = say("Hi Clinton, how was the launch yesterday?", from: 1.0, speaker: 0)
        let mic = say("Hi Clinton, how was the lunch yesterday?", from: 1.1, speaker: 0)
            + say("Good.", from: 6.0, speaker: 0)
        let result = TurnBuilder.build(channels: [mic, far], twoTrack: true)
        XCTAssertEqual(result.text, "Hi Clinton, how was the launch yesterday? Good.")
    }

    func testDifferentWordsAtTheSameTimeSurvive() {
        let far = say("Hi Clinton, how was the launch yesterday?", from: 1.0, speaker: 0)
        let mic = say("Yes exactly.", from: 2.0, speaker: 0)
        XCTAssertTrue(TurnBuilder.build(channels: [mic, far], twoTrack: true).text.contains("Yes exactly."))
    }

    func testFarSideInterjectionLandsBetweenSentences() {
        let mic = say("First we fix the recorder. Then we ship the model change. After that we write the audit.", from: 0, speaker: 0)
        let far = say("Makes sense.", from: 3.2, speaker: 0)
        let result = TurnBuilder.build(channels: [mic, far], twoTrack: true)
        XCTAssertEqual(result.turns?.map(\.speaker), [0, 1, 0])
    }

    func testFarSideSpeakersMapAfterTheMic() {
        let far = say("Let's start with the numbers.", from: 0, speaker: 0)
            + say("Revenue is up twelve percent.", from: 2.5, speaker: 1)
        let result = TurnBuilder.build(channels: [say("Nice.", from: 5, speaker: 0), far], twoTrack: true)
        XCTAssertEqual(result.turns?.map(\.speaker), [1, 2, 0])
    }

    func testEmptyChannelsGiveEmptyText() {
        let result = TurnBuilder.build(channels: [[], []], twoTrack: true)
        XCTAssertTrue(result.text.isEmpty)
        XCTAssertNil(result.turns)
    }

    func testTwoTrackRequestWithOneChannelStaysPlain() {
        let result = TurnBuilder.build(channels: [say("Just me.", from: 0, speaker: 0)], twoTrack: true)
        XCTAssertNil(result.turns)
        XCTAssertEqual(result.text, "Just me.")
    }

    func testAnHourOfTwoTrackWordsBuildsQuickly() {
        var mic: [TimedWord] = [], far: [TimedWord] = []
        for i in 0..<9000 {
            let t = Double(i) * 0.4
            far.append(TimedWord(text: "word\(i % 50)", start: t, end: t + 0.3, speaker: i / 300 % 2))
            if i % 3 == 0 { mic.append(TimedWord(text: "word\(i % 50)", start: t + 0.1, end: t + 0.4, speaker: 0)) }
        }
        let started = Date()
        _ = TurnBuilder.build(channels: [mic, far], twoTrack: true)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
    }
}
