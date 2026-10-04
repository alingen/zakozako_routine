import SwiftUI
import XCTest
@testable import MesugakiRoutine

@MainActor
final class StoryVoicePlaybackTests: XCTestCase {
    private final class Audio: StoryVoiceAudioPlayer {
        var onCompletion: (() -> Void)?
        var plays = 0
        var stops = 0
        var succeeds = true
        func play() -> Bool { plays += 1; return succeeds }
        func stop() { stops += 1 }
    }

    private func line(_ id: String = "one", voice: String? = "voice_rio") -> StoryNode {
        StoryNode(nodeId: id, lineOrder: 1, speaker: "rio", messageType: .text,
                  text: "こんにちは", voiceAssetId: voice, screenMode: .adv)
    }

    private func controller(_ audio: Audio) -> StoryVoicePlaybackController {
        StoryVoicePlaybackController(
            resolveURL: { _ in URL(fileURLWithPath: "/test.m4a") }, makePlayer: { _ in audio }
        )
    }

    func testVoiceDecodesAndOldContentRemainsCompatible() throws {
        let old = Data(#"{"nodeId":"one","lineOrder":1,"speaker":"rio","messageType":"text"}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(StoryNode.self, from: old).voiceAssetId)
        let voiced = StoryNode(nodeId: "one", lineOrder: 1, speaker: "rio", messageType: .text,
                               voiceAssetId: "voice_rio", voiceFileName: "take_02.m4a")
        XCTAssertEqual(try JSONDecoder().decode(StoryNode.self, from: JSONEncoder().encode(voiced)), voiced)
    }

    func testAutoWaitsUntilVoiceCompletesAndStartsOncePerLine() {
        let audio = Audio()
        let playback = controller(audio)
        let node = line()
        XCTAssertTrue(playback.awaitsCompletion(for: node), "Wait for the reveal task to start voice")
        playback.start(node: node)
        playback.start(node: node) // Pagination or toggling auto must not restart voice.
        XCTAssertEqual(audio.plays, 1)
        XCTAssertTrue(playback.awaitsCompletion(for: node))
        audio.onCompletion?()
        XCTAssertFalse(playback.awaitsCompletion(for: node))
        playback.start(node: node)
        XCTAssertEqual(audio.plays, 1)
    }

    func testNextLineStopsPreviousVoiceAndIgnoresStaleCompletion() {
        let first = Audio()
        let second = Audio()
        var players = [first, second]
        let playback = StoryVoicePlaybackController(
            resolveURL: { _ in URL(fileURLWithPath: "/test.wav") }, makePlayer: { _ in players.removeFirst() }
        )
        playback.start(node: line())
        let staleCompletion = first.onCompletion
        playback.select(nodeID: "two")
        XCTAssertEqual(first.stops, 1)
        playback.start(node: line("two"))
        staleCompletion?()
        XCTAssertTrue(playback.isPlaying)
        XCTAssertEqual(second.stops, 0)
    }

    func testFastForwardStopsAndSuppressesUntilNextLine() {
        let audio = Audio()
        let playback = controller(audio)
        playback.start(node: line())
        playback.suppress(nodeID: "one")
        XCTAssertFalse(playback.awaitsCompletion(for: line()))
        XCTAssertEqual(audio.stops, 1)
        playback.start(node: line())
        XCTAssertEqual(audio.plays, 1)
        playback.start(node: line("two"))
        XCTAssertEqual(audio.plays, 2)
    }

    func testLineEnteredDuringFastForwardDoesNotPlay() {
        let audio = Audio()
        let playback = controller(audio)
        playback.suppress(nodeID: "one")
        playback.start(node: line())
        XCTAssertEqual(audio.plays, 0)
        XCTAssertFalse(playback.awaitsCompletion(for: line()))
    }

    func testSkipCloseOrInterruptionStopsAndDoesNotReplayCurrentLine() {
        let audio = Audio()
        let playback = controller(audio)
        playback.start(node: line())
        playback.stop()
        playback.start(node: line())
        XCTAssertEqual(audio.stops, 1)
        XCTAssertEqual(audio.plays, 1)
        XCTAssertFalse(playback.awaitsCompletion(for: line()))
    }

    func testMissingFailedAndUnvoicedLinesDoNotBlockAuto() {
        let missing = StoryVoicePlaybackController(resolveURL: { _ in nil })
        missing.start(node: line())
        XCTAssertNotNil(missing.diagnostic)
        XCTAssertFalse(missing.awaitsCompletion(for: line()))
        let audio = Audio()
        audio.succeeds = false
        let failed = controller(audio)
        failed.start(node: line())
        XCTAssertFalse(failed.awaitsCompletion(for: line()))
        XCTAssertNotNil(failed.diagnostic)
        let unvoiced = line("unvoiced", voice: nil)
        XCTAssertFalse(failed.awaitsCompletion(for: unvoiced))
        failed.start(node: unvoiced)
        XCTAssertEqual(audio.plays, 1)
    }

    func testRevisitingALineCanPlayAgain() {
        let audio = Audio()
        let playback = controller(audio)
        playback.start(node: line())
        playback.select(nodeID: "other")
        playback.start(node: line())
        XCTAssertEqual(audio.plays, 2)
    }

    func testVoiceFileNameResolvesExistingBundleAudio() {
        let node = StoryNode(nodeId: "one", lineOrder: 1, speaker: "rio", messageType: .text,
                             voiceAssetId: "catalog_id_different_from_file", voiceFileName: "se_click.mp3")
        XCTAssertEqual(StoryVoiceResource.url(for: node)?.lastPathComponent, "se_click.mp3")
        let unsafe = StoryNode(nodeId: "one", lineOrder: 1, speaker: "rio", messageType: .text,
                               voiceAssetId: "voice", voiceFileName: "../secret.mp3")
        XCTAssertNil(StoryVoiceResource.url(for: unsafe))
    }
}
