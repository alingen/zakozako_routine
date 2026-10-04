import XCTest
@testable import MesugakiRoutine

final class StoryBGMStopCommandTests: XCTestCase {
    func testStopDefaultsToOneSecondAndHonorsExplicitDurationIncludingZero() {
        let cases: [(JSONValue?, UInt64)] = [
            (nil, 1_000), (.object(["action": .string("stop")]), 1_000),
            (.object(["fade_ms": .number(1_500)]), 1_500),
            (.object(["fade_ms": .number(0)]), 0),
            (.object(["fade_ms": .string("0")]), 0),
        ]
        for (args, expected) in cases {
            let result = dispatch(args)
            XCTAssertEqual(result.effects, [.stopBGM(fadeMilliseconds: expected)])
            XCTAssertNil(result.diagnostic)
        }
    }

    func testInvalidOrOutOfRangeDurationsAreSafe() {
        let cases: [(JSONValue, UInt64)] = [
            (.number(-10), 0), (.number(50_000), 10_000),
            (.string("invalid"), 1_000), (.null, 1_000),
            (.number(.infinity), 1_000), (.number(.nan), 1_000),
        ]
        for (value, expected) in cases {
            XCTAssertEqual(dispatch(.object(["fade_ms": value])).effects,
                           [.stopBGM(fadeMilliseconds: expected)])
        }
    }

    private func dispatch(_ args: JSONValue?) -> StoryCommandDispatchResult {
        StoryCommandDispatcher().dispatch(node: StoryNode(
            nodeId: "stop", lineOrder: 1, speaker: "system", messageType: .action,
            command: "stop_bgm", commandArgs: args
        ))
    }
}

@MainActor
final class StoryBGMPlaybackTests: XCTestCase {
    private final class AudioProbe: StoryBGMAudioPlayer {
        var volume: Float = 1
        var numberOfLoops = 0
        var isPlaying = false
        var stopCount = 0
        var fades: [(volume: Float, duration: TimeInterval)] = []
        var onStop: (() -> Void)?
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { isPlaying = true; return true }
        func setVolume(_ volume: Float, fadeDuration duration: TimeInterval) {
            fades.append((volume, duration))
        }
        func stop() { isPlaying = false; stopCount += 1; onStop?() }
    }

    private final class FadeGate {
        var waits: [UInt64] = []
        var onWait: (() -> Void)?
        private var continuations: [CheckedContinuation<Void, Never>] = []
        func wait(_ milliseconds: UInt64) async {
            waits.append(milliseconds)
            await withCheckedContinuation {
                continuations.append($0)
                onWait?()
            }
        }
        func release() {
            let pending = continuations
            continuations = []
            pending.forEach { $0.resume() }
        }
    }

    private func state(_ id: String = "bgm", fadeIn: UInt64 = 0) -> StoryBGMPlaybackState {
        StoryBGMPlaybackState(assetID: id, loop: true, fadeMilliseconds: fadeIn, volume: 0.4)
    }

    func testDefaultStopFadesToSilenceBeforeStoppingAndDoesNotRestartFade() async {
        let audio = AudioProbe()
        let gate = FadeGate()
        let waiting = expectation(description: "Fade wait started")
        gate.onWait = { waiting.fulfill() }
        let stopped = expectation(description: "Old track stopped after fade")
        audio.onStop = { stopped.fulfill() }
        let controller = StoryBGMPlaybackController(makePlayer: { _ in audio },
                                                    configureAudioSession: {}, sleep: gate.wait)
        controller.synchronize(with: .init(state: state(), events: []))
        XCTAssertEqual(audio.volume, 0.4)
        XCTAssertEqual(audio.numberOfLoops, -1)

        controller.stop()
        controller.stop() // onDisappear may follow a scripted stop.
        XCTAssertTrue(audio.isPlaying)
        XCTAssertEqual(audio.stopCount, 0)
        XCTAssertEqual(audio.fades.map(\.volume), [0])
        XCTAssertEqual(audio.fades.map(\.duration), [1])
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertEqual(gate.waits, [1_000])
        gate.release()
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertFalse(audio.isPlaying)
    }

    func testCustomFadeCannotStopNewTrackAndPreservesFadeIn() async {
        let old = AudioProbe()
        let new = AudioProbe()
        let gate = FadeGate()
        let waiting = expectation(description: "Custom fade wait")
        gate.onWait = { waiting.fulfill() }
        let stopped = expectation(description: "Only old track stops")
        old.onStop = { stopped.fulfill() }
        let controller = StoryBGMPlaybackController(makePlayer: { $0 == "old" ? old : new },
                                                    configureAudioSession: {}, sleep: gate.wait)
        controller.synchronize(with: .init(state: state("old"), events: []))
        let newState = state("new", fadeIn: 250)
        controller.synchronize(with: .init(state: newState, events: [
            .stop(fadeMilliseconds: 1_500), .play(newState),
        ]))
        XCTAssertEqual(old.fades.map(\.duration), [1.5])
        XCTAssertEqual(new.volume, 0)
        XCTAssertEqual(new.fades.map(\.volume), [0.4])
        XCTAssertEqual(new.fades.map(\.duration), [0.25])
        XCTAssertTrue(old.isPlaying)
        XCTAssertTrue(new.isPlaying)
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertEqual(gate.waits, [1_500])
        gate.release()
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertTrue(new.isPlaying)
        XCTAssertEqual(new.stopCount, 0)
        controller.stop(fadeMilliseconds: 0)
    }

    func testImmediateStopThenSameTrackPlayIsNotLostInOneUpdate() {
        var players: [AudioProbe] = []
        let controller = StoryBGMPlaybackController(makePlayer: { _ in
            let audio = AudioProbe()
            players.append(audio)
            return audio
        }, configureAudioSession: {}, sleep: { _ in XCTFail("An immediate stop must not wait") })
        let music = state()
        controller.synchronize(with: .init(state: music, events: [.play(music)]))
        controller.synchronize(with: .init(state: music, events: [.stop(fadeMilliseconds: 0), .play(music)]))
        XCTAssertEqual(players.count, 2)
        XCTAssertEqual(players.map(\.isPlaying), [false, true])
        XCTAssertEqual(players.map(\.stopCount), [1, 0])
        XCTAssertTrue(players.allSatisfy { $0.fades.isEmpty })
        // Draining the event queue causes another update but must not restart the music.
        controller.synchronize(with: .init(state: music, events: []))
        XCTAssertEqual(players.count, 2)
        controller.stop(fadeMilliseconds: 0)
    }

    func testImmediateStopAlsoCancelsAnOlderTrackThatIsStillFading() async {
        let old = AudioProbe()
        let new = AudioProbe()
        let gate = FadeGate()
        let waiting = expectation(description: "Replacement fades the old BGM by default")
        gate.onWait = { waiting.fulfill() }
        let controller = StoryBGMPlaybackController(makePlayer: { $0 == "old" ? old : new },
                                                    configureAudioSession: {}, sleep: gate.wait)
        controller.synchronize(with: .init(state: state("old"), events: []))
        controller.synchronize(with: .init(state: state("new"), events: [.play(state("new"))]))
        await fulfillment(of: [waiting], timeout: 1)
        XCTAssertEqual(old.fades.map(\.duration), [1])
        controller.synchronize(with: .init(state: nil, events: [.stop(fadeMilliseconds: 0)]))
        XCTAssertFalse(old.isPlaying)
        XCTAssertFalse(new.isPlaying)
        XCTAssertEqual(old.stopCount, 1)
        XCTAssertEqual(new.stopCount, 1)
        gate.release()
    }

    func testFadeFinishesEvenAfterTheViewReleasesItsController() async {
        let audio = AudioProbe()
        let gate = FadeGate()
        let waiting = expectation(description: "Dismissal fade started")
        gate.onWait = { waiting.fulfill() }
        let stopped = expectation(description: "Dismissed view's audio stops")
        audio.onStop = { stopped.fulfill() }
        var controller: StoryBGMPlaybackController? = StoryBGMPlaybackController(
            makePlayer: { _ in audio }, configureAudioSession: {}, sleep: gate.wait
        )
        let isControllerReleased = { [weak controller] in controller == nil }
        controller?.synchronize(with: .init(state: state(), events: []))
        controller?.stop()
        controller = nil
        XCTAssertTrue(isControllerReleased())
        XCTAssertTrue(audio.isPlaying)
        await fulfillment(of: [waiting], timeout: 1)
        gate.release()
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertEqual(audio.stopCount, 1)
    }
}
