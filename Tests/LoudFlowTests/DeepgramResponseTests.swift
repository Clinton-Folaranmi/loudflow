import XCTest

final class DeepgramResponseTests: XCTestCase {

    private func decode(_ json: String) throws -> [DeepgramResponse.Channel] {
        let response = try JSONDecoder().decode(DeepgramResponse.self, from: Data(json.utf8))
        return try XCTUnwrap(response.results?.channels)
    }

    func testMultichannelResponseDropsEchoAndLabelsSides() throws {
        let channels = try decode("""
        {"metadata":{"diarize_info":{"arch":"v2"}},"results":{"channels":[
         {"alternatives":[{"transcript":"hi clinton how was the launch yesterday it went great","words":[
          {"word":"hi","punctuated_word":"Hi","start":1.12,"end":1.3,"speaker":0,"speaker_confidence":0.4},
          {"word":"clinton","punctuated_word":"Clinton,","start":1.4,"end":1.8,"speaker":0},
          {"word":"how","punctuated_word":"how","start":1.9,"end":2.0,"speaker":0},
          {"word":"was","punctuated_word":"was","start":2.05,"end":2.2,"speaker":0},
          {"word":"the","punctuated_word":"the","start":2.25,"end":2.3,"speaker":0},
          {"word":"launch","punctuated_word":"launch","start":2.35,"end":2.7,"speaker":0},
          {"word":"yesterday","punctuated_word":"yesterday?","start":2.75,"end":3.3,"speaker":0},
          {"word":"it","punctuated_word":"It","start":5.0,"end":5.1,"speaker":0},
          {"word":"went","punctuated_word":"went","start":5.15,"end":5.3,"speaker":0},
          {"word":"great","punctuated_word":"great.","start":5.35,"end":5.7,"speaker":0}]}]},
         {"alternatives":[{"transcript":"hi clinton how was the launch yesterday","words":[
          {"word":"hi","punctuated_word":"Hi","start":1.0,"end":1.2,"speaker":0},
          {"word":"clinton","punctuated_word":"Clinton,","start":1.3,"end":1.7,"speaker":0},
          {"word":"how","punctuated_word":"how","start":1.8,"end":1.9,"speaker":0},
          {"word":"was","punctuated_word":"was","start":1.95,"end":2.1,"speaker":0},
          {"word":"the","punctuated_word":"the","start":2.15,"end":2.2,"speaker":0},
          {"word":"launch","punctuated_word":"launch","start":2.25,"end":2.6,"speaker":0},
          {"word":"yesterday","punctuated_word":"yesterday?","start":2.65,"end":3.2,"speaker":0}]}]}
        ]}}
        """)
        let result = DeepgramTranscriber.result(from: channels, twoTrack: true)
        XCTAssertEqual(result.text, "Hi Clinton, how was the launch yesterday? It went great.")
        XCTAssertEqual(result.turns?.map(\.speaker), [1, 0])
        XCTAssertEqual(result.turns?.last?.end, 5.7)
    }

    func testTranscriptOnlyResponseFallsBackToPlainText() throws {
        let channels = try decode(#"{"results":{"channels":[{"alternatives":[{"transcript":"  hello there  "}]}]}}"#)
        let result = DeepgramTranscriber.result(from: channels, twoTrack: false)
        XCTAssertEqual(result.text, "hello there")
        XCTAssertNil(result.turns)
    }
}
