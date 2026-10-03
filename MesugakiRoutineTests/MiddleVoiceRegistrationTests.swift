import AVFoundation
import XCTest
@testable import MesugakiRoutine

final class MiddleVoiceRegistrationTests: XCTestCase {
    func testAllRegisteredMiddleVoicesAreBundledAndDecodable() throws {
        let bundle = Bundle(for: StoryPlayer.self)
        let url = try XCTUnwrap(bundle.url(forResource: "story_content.generated", withExtension: "json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let scenarios = try XCTUnwrap(json["scenarios"] as? [[String: Any]])
        let scenario = try XCTUnwrap(scenarios.first { $0["scenarioId"] as? String == "middle_001_1" })
        let nodes = try XCTUnwrap(scenario["nodes"] as? [[String: Any]])
        let voices = nodes.compactMap { $0["voiceFileName"] as? String }
        XCTAssertEqual(voices.count, 14)
        XCTAssertEqual(Set(voices).count, 13)
        for name in Set(voices) {
            let audioURL = try XCTUnwrap(bundle.url(forResource: name, withExtension: nil), name)
            let audio = try AVAudioPlayer(contentsOf: audioURL)
            XCTAssertGreaterThan(audio.duration, 0)
        }
    }
}
