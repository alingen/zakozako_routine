import Foundation
import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class StorySceneTransitionTests: XCTestCase {
    private var retainedContainers: [ModelContainer] = []

    func testDefaultConfigurationMatchesSevenHundredMillisecondSlide() throws {
        let configuration = try XCTUnwrap(configuration(["type": .string("colorSlide")]))

        XCTAssertEqual(configuration.type, .colorSlide)
        XCTAssertEqual(configuration.duration, 0.70, accuracy: 0.0001)
        XCTAssertEqual(configuration.coverDuration, 0.28, accuracy: 0.0001)
        XCTAssertEqual(configuration.minimumHold, 0.08, accuracy: 0.0001)
        XCTAssertEqual(configuration.revealDuration, 0.34, accuracy: 0.0001)
    }

    func testPhaseDurationsAreNormalizedToRequestedTotal() throws {
        let configuration = try XCTUnwrap(configuration([
            "type": .string("colorSlide"),
            "duration": .number(1.2),
            "minimumHold": .number(0.2),
            "coverDuration": .number(0.1),
            "revealDuration": .number(0.3),
        ]))

        XCTAssertEqual(configuration.duration, 1.2)
        XCTAssertEqual(configuration.minimumHold, 0.2)
        XCTAssertEqual(configuration.coverDuration, 0.25, accuracy: 0.0001)
        XCTAssertEqual(configuration.revealDuration, 0.75, accuracy: 0.0001)
    }

    func testMalformedAndOutOfRangeValuesCannotProduceInvalidTiming() throws {
        let clamped = try XCTUnwrap(configuration([
            "type": .string("colorSlide"),
            "duration": .number(-1),
            "minimumHold": .number(50),
        ]))
        XCTAssertEqual(clamped.duration, 0.15)
        XCTAssertEqual(clamped.minimumHold, 0.05, accuracy: 0.0001)
        XCTAssertGreaterThan(clamped.coverDuration, 0)
        XCTAssertGreaterThan(clamped.revealDuration, 0)
        let fallback = try XCTUnwrap(configuration([
            "type": .string("colorSlide"),
            "duration": .string("NaN"),
            "minimumHold": .object([:]),
            "coverDuration": .bool(false),
        ]))
        XCTAssertEqual(fallback.duration, 0.70)
        XCTAssertEqual(fallback.minimumHold, 0.08)
        XCTAssertEqual(fallback.coverDuration, 0.28, accuracy: 0.0001)
    }

    func testLegacyAndUnknownTransitionsRemainOptOut() {
        XCTAssertNil(StorySceneTransitionConfiguration(arguments: nil))
        XCTAssertNil(StorySceneTransitionConfiguration(arguments: .object([:])))
        XCTAssertNil(configuration(["type": .string("fade")]))
        XCTAssertNil(configuration(["type": .string("futureTransition")]))
        XCTAssertNil(StorySceneTransitionConfiguration(arguments: .object([
            "transition": .bool(true),
        ])))
        XCTAssertNotNil(StorySceneTransitionConfiguration(arguments: .object([
            "transition": .string("colorSlide"),
        ])))
        XCTAssertEqual(configuration([
            "type": .string("pixelSpiral"),
            "turns": .number(1.5),
            "direction": .string("clockwise"),
            "blockSize": .string("default"),
        ])?.type, .colorSlide,
                       "Previously-authored scene commands should keep their transition")
    }

    func testReduceMotionIsShortAndExplicitCrossFadeHonorsConfiguredTiming() throws {
        let slide = try XCTUnwrap(configuration(["type": .string("colorSlide")]))
        let crossFade = try XCTUnwrap(configuration(["type": .string("crossFade")]))
        XCTAssertEqual(slide.effectiveCoverDuration(reduceMotion: true), 0.10)
        XCTAssertEqual(slide.effectiveRevealDuration(reduceMotion: true), 0.12)
        XCTAssertEqual(crossFade.effectiveCoverDuration(reduceMotion: false), 0.28, accuracy: 0.0001)
        XCTAssertEqual(crossFade.effectiveRevealDuration(reduceMotion: false), 0.34, accuracy: 0.0001)
        XCTAssertEqual(slide.effectiveCoverDuration(reduceMotion: false), 0.28, accuracy: 0.0001)
    }

    func testSlideCoversPortraitLandscapeAndFractionalViewportSizes() {
        for size in [
            CGSize(width: 320, height: 568),
            CGSize(width: 393, height: 852),
            CGSize(width: 852, height: 393),
            CGSize(width: 1024, height: 1366),
            CGSize(width: 391.3, height: 844.6),
        ] {
            let start = StorySlideTransitionGeometry.coveredRect(size: size, progress: 0, phase: .covering)
            let halfway = StorySlideTransitionGeometry.coveredRect(size: size, progress: 0.5, phase: .covering)
            let fullyCovered = StorySlideTransitionGeometry.coveredRect(size: size, progress: 1, phase: .covering)
            let swap = StorySlideTransitionGeometry.coveredRect(size: size, progress: 0, phase: .covered)
            let revealStart = StorySlideTransitionGeometry.coveredRect(size: size, progress: 0, phase: .revealing)
            let revealHalfway = StorySlideTransitionGeometry.coveredRect(size: size, progress: 0.5, phase: .revealing)
            let end = StorySlideTransitionGeometry.coveredRect(size: size, progress: 1, phase: .revealing)

            XCTAssertEqual(start, CGRect(x: 0, y: size.height, width: size.width, height: 0))
            XCTAssertEqual(halfway.minY, size.height / 2, accuracy: 0.0001)
            XCTAssertEqual(halfway.height, size.height / 2, accuracy: 0.0001)
            XCTAssertEqual(fullyCovered, CGRect(origin: .zero, size: size))
            XCTAssertEqual(swap, fullyCovered, "No screen edge may show while swapping scenes")
            XCTAssertEqual(revealStart, fullyCovered)
            XCTAssertEqual(revealHalfway.minY, size.height / 2, accuracy: 0.0001)
            XCTAssertEqual(revealHalfway.height, size.height / 2, accuracy: 0.0001)
            XCTAssertEqual(end, start)
            XCTAssertEqual(
                StorySlideTransitionGeometry.panelOriginY(height: size.height, progress: 0.5, phase: .covering)
                    + size.height,
                size.height * 1.5,
                accuracy: 0.0001,
                "The moving full-height panel must extend past the bottom edge"
            )
        }
    }

    func testSlideMovementIsMonotonicAndClamped() {
        let size = CGSize(width: 393, height: 852)
        var previousCoverHeight: CGFloat = 0
        var previousRevealHeight = size.height
        for step in 0...100 {
            let progress = Double(step) / 100
            let covering = StorySlideTransitionGeometry.coveredRect(size: size, progress: progress, phase: .covering).height
            let revealing = StorySlideTransitionGeometry.coveredRect(size: size, progress: progress, phase: .revealing).height
            XCTAssertGreaterThanOrEqual(covering, previousCoverHeight)
            XCTAssertLessThanOrEqual(revealing, previousRevealHeight)
            XCTAssertGreaterThanOrEqual(covering, 0)
            XCTAssertLessThanOrEqual(covering, size.height)
            XCTAssertGreaterThanOrEqual(revealing, 0)
            XCTAssertLessThanOrEqual(revealing, size.height)
            previousCoverHeight = covering
            previousRevealHeight = revealing
        }
        XCTAssertEqual(previousCoverHeight, size.height)
        XCTAssertEqual(StorySlideTransitionGeometry.coveredRect(size: size, progress: 0, phase: .covered).height, size.height)
        XCTAssertEqual(StorySlideTransitionGeometry.coveredRect(size: size, progress: -100, phase: .covering).height, 0)
        XCTAssertEqual(StorySlideTransitionGeometry.coveredRect(size: size, progress: 100, phase: .revealing).height, 0)
    }

    func testLoadingDotsAreVisibleOnlyAroundFullCoverage() {
        XCTAssertFalse(StorySlideTransitionGeometry.showsIndicator(progress: 0, phase: .covering))
        XCTAssertFalse(StorySlideTransitionGeometry.showsIndicator(progress: 0.49, phase: .covering))
        XCTAssertFalse(StorySlideTransitionGeometry.showsIndicator(progress: 0.5, phase: .covering))
        XCTAssertTrue(StorySlideTransitionGeometry.showsIndicator(progress: 0.51, phase: .covering))
        XCTAssertTrue(StorySlideTransitionGeometry.showsIndicator(progress: 1, phase: .covering))
        XCTAssertTrue(StorySlideTransitionGeometry.showsIndicator(progress: 0, phase: .covered))
        XCTAssertFalse(StorySlideTransitionGeometry.showsIndicator(progress: 0.5, phase: .revealing))
        XCTAssertTrue(StorySlideTransitionGeometry.showsIndicator(progress: 0.49, phase: .revealing))
        XCTAssertFalse(StorySlideTransitionGeometry.showsIndicator(progress: 0.51, phase: .revealing))
        XCTAssertFalse(StorySlideTransitionGeometry.showsIndicator(progress: 1, phase: .revealing))
    }

    func testOldSceneIsHeldUntilFullyCoveredAndNewSceneIsReadyBeforeReveal() async throws {
        let probe = TransitionProbe()
        let player = try makePlayer(probe: probe)
        await player.start()
        XCTAssertEqual(player.currentNode?.nodeId, "old")
        let didPrefetch = await eventually { probe.requestedAssetIDs.contains("bg_new") }
        XCTAssertTrue(didPrefetch, "The upcoming scene should preload while the old dialogue is visible")

        await player.advance()

        let covering = try XCTUnwrap(probe.sleeps.first { $0.snapshot.phase == .covering })
        XCTAssertEqual(covering.snapshot.nodeID, "old")
        XCTAssertEqual(covering.snapshot.background, "bg_old")
        XCTAssertEqual(covering.snapshot.portrait, "portrait_old")

        let beforeSwap = try XCTUnwrap(probe.barriers.first)
        XCTAssertEqual(beforeSwap.phase, .covered)
        XCTAssertEqual(beforeSwap.background, "bg_old")
        XCTAssertEqual(beforeSwap.portrait, "portrait_old")
        let afterSwap = try XCTUnwrap(probe.barriers.last)
        XCTAssertEqual(afterSwap.phase, .covered)
        XCTAssertEqual(afterSwap.background, "bg_new")
        XCTAssertEqual(afterSwap.portrait, "portrait_new")
        XCTAssertGreaterThanOrEqual(probe.barriers.count, 2)
        XCTAssertTrue(probe.barriers.allSatisfy { !$0.isWaitingForAssets })

        let reveal = try XCTUnwrap(probe.sleeps.first { $0.snapshot.phase == .revealing })
        XCTAssertEqual(reveal.snapshot.nodeID, "new")
        XCTAssertEqual(reveal.snapshot.background, "bg_new")
        XCTAssertEqual(reveal.snapshot.portrait, "portrait_new")
        XCTAssertEqual(player.currentNode?.text, "新しい場面")
        XCTAssertNil(player.sceneTransition)
        XCTAssertFalse(player.isCompleted)
        XCTAssertNil(player.recoverableError)
        XCTAssertTrue(probe.requestedAssetIDs.contains("bg_new"))
        XCTAssertTrue(probe.requestedAssetIDs.contains("portrait_new"))
        XCTAssertEqual(probe.sleeps.reduce(0) { $0 + $1.milliseconds }, 700)
        XCTAssertEqual(
            player.consumePendingSoundEffects(),
            [StorySoundEffectPlayback(assetID: "se_color_slide", volume: 1)]
        )
        XCTAssertTrue(player.consumePendingSoundEffects().isEmpty, "Play the slide SE only once")
    }

    func testRapidRepeatedAdvanceDoesNotSkipTheNewDialogue() async throws {
        let probe = TransitionProbe()
        let coverGate = TransitionGate()
        probe.coverGate = coverGate
        let player = try makePlayer(probe: probe)
        await player.start()

        let firstAdvance = Task { await player.advance(expectedNodeId: "old") }
        let didBeginCover = await eventually { coverGate.isWaiting }
        XCTAssertTrue(didBeginCover)
        for _ in 0..<10 { await player.advance() }
        XCTAssertEqual(player.currentNode?.nodeId, "old")
        XCTAssertEqual(player.sceneTransition?.phase, .covering)

        coverGate.release()
        await firstAdvance.value
        XCTAssertEqual(player.currentNode?.nodeId, "new")
        XCTAssertFalse(player.isCompleted)
        XCTAssertNil(player.sceneTransition)
        XCTAssertEqual(probe.sleeps.filter { $0.snapshot.phase == .covering }.count, 1)
    }

    func testPendingAssetsKeepScreenCoveredAndOnlyThenAllowReveal() async throws {
        let probe = TransitionProbe()
        let assetGate = TransitionGate()
        probe.assetGate = assetGate
        let player = try makePlayer(probe: probe)
        await player.start()

        let advance = Task { await player.advance() }
        let didWaitForAssets = await eventually {
            player.sceneTransition?.phase == .covered
                && player.sceneTransition?.isWaitingForAssets == true
        }
        XCTAssertTrue(didWaitForAssets)
        XCTAssertEqual(player.backgroundAssetID, "bg_old")
        XCTAssertFalse(probe.sleeps.contains { $0.snapshot.phase == .revealing })
        await player.advance()
        XCTAssertFalse(player.isCompleted)

        assetGate.release()
        await advance.value
        XCTAssertEqual(player.currentNode?.nodeId, "new")
        XCTAssertNil(player.sceneTransition)
        XCTAssertTrue(probe.sleeps.contains { $0.snapshot.phase == .revealing })
    }

    func testCloseDuringCoverCancelsTransitionAndReleasesInputLock() async throws {
        let probe = TransitionProbe()
        let coverGate = TransitionGate()
        probe.coverGate = coverGate
        let player = try makePlayer(probe: probe)
        await player.start()

        let advance = Task { await player.advance() }
        let didBeginCover = await eventually { coverGate.isWaiting }
        XCTAssertTrue(didBeginCover)
        player.close()
        XCTAssertNil(player.sceneTransition)
        coverGate.release()
        await advance.value
        XCTAssertEqual(player.backgroundAssetID, "bg_old")
        XCTAssertFalse(probe.sleeps.contains { $0.snapshot.phase == .revealing })

        probe.coverGate = nil
        await player.restart()
        XCTAssertEqual(player.currentNode?.nodeId, "old")
        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "new")
        XCTAssertNil(player.sceneTransition)
    }

    func testCloseWhileWaitingForAssetsDoesNotResurrectOverlayOrApplyNewScene() async throws {
        let probe = TransitionProbe()
        let assetGate = TransitionGate()
        probe.assetGate = assetGate
        let player = try makePlayer(probe: probe)
        await player.start()
        let advance = Task { await player.advance() }
        let didWait = await eventually { player.sceneTransition?.isWaitingForAssets == true }
        XCTAssertTrue(didWait)

        player.close()
        XCTAssertNil(player.sceneTransition)
        assetGate.release()
        await advance.value
        XCTAssertNil(player.sceneTransition)
        XCTAssertEqual(player.backgroundAssetID, "bg_old")
        XCTAssertEqual(player.currentNode?.nodeId, "old")
        XCTAssertFalse(probe.sleeps.contains { $0.snapshot.phase == .revealing })
    }

    func testSceneChangeWithoutConfigurationKeepsExistingProgression() async throws {
        let probe = TransitionProbe()
        let player = try makePlayer(probe: probe, transitionArguments: nil)
        await player.start()
        await player.advance()

        XCTAssertEqual(player.currentNode?.nodeId, "new")
        XCTAssertEqual(player.backgroundAssetID, "bg_new")
        XCTAssertEqual(player.portraitAssetID, "portrait_new")
        XCTAssertTrue(probe.barriers.isEmpty)
        XCTAssertTrue(probe.sleeps.isEmpty)
        XCTAssertNil(player.sceneTransition)
        XCTAssertTrue(player.consumePendingSoundEffects().isEmpty)
    }

    func testExplicitCrossFadeDoesNotPlayColorSlideSound() async throws {
        let probe = TransitionProbe()
        let player = try makePlayer(probe: probe, transitionArguments: .object([
            "transition": .object(["type": .string("crossFade")]),
        ]))
        await player.start()
        await player.advance()

        XCTAssertEqual(player.currentNode?.nodeId, "new")
        XCTAssertTrue(player.consumePendingSoundEffects().isEmpty)
    }

    func testInitialSceneDoesNotAnimateWithoutAnOldScene() async throws {
        let probe = TransitionProbe()
        let player = try makePlayer(probe: probe, startsWithTransition: true)
        await player.start()

        XCTAssertEqual(player.currentNode?.nodeId, "new")
        XCTAssertEqual(player.backgroundAssetID, "bg_new")
        XCTAssertTrue(probe.barriers.isEmpty)
        XCTAssertTrue(probe.sleeps.isEmpty)
        XCTAssertNil(player.sceneTransition)
        XCTAssertTrue(player.consumePendingSoundEffects().isEmpty)
    }

    func testCompletedTransitionIsNotReplayedWhenRestoringCheckpoint() async throws {
        let probe = TransitionProbe()
        let player = try makePlayer(probe: probe)
        await player.start()
        await player.advance()
        player.close()
        probe.sleeps.removeAll()
        probe.barriers.removeAll()

        await player.start()
        XCTAssertEqual(player.currentNode?.nodeId, "new")
        XCTAssertEqual(player.backgroundAssetID, "bg_new")
        XCTAssertTrue(probe.barriers.isEmpty)
        XCTAssertTrue(probe.sleeps.isEmpty)
        XCTAssertNil(player.sceneTransition)
    }

    private func configuration(_ fields: [String: JSONValue]) -> StorySceneTransitionConfiguration? {
        StorySceneTransitionConfiguration(arguments: .object(["transition": .object(fields)]))
    }

    private func makePlayer(
        probe: TransitionProbe,
        transitionArguments: JSONValue? = .object([
            "transition": .object(["type": .string("colorSlide")]),
        ]),
        startsWithTransition: Bool = false
    ) throws -> StoryPlayer {
        let old = StoryNode(
            nodeId: "old", lineOrder: 1, speaker: "rio", messageType: .text,
            text: "前の場面", background: "bg_old", portrait: "portrait_old", screenMode: .adv
        )
        let change = StoryNode(
            nodeId: "change", lineOrder: 2, speaker: "system", messageType: .action,
            background: "bg_new", portrait: "portrait_new", screenMode: .adv,
            uiVariant: .sceneTransition, command: "scene_change", commandArgs: transitionArguments
        )
        let new = StoryNode(
            nodeId: "new", lineOrder: 3, speaker: "rio", messageType: .text,
            text: "新しい場面", screenMode: .adv
        )
        let scenario = StoryScenario(
            scenarioId: "slide_transition_test", scenarioType: .middleEvent,
            nodes: (startsWithTransition ? [] : [old]) + [change, new]
        )
        let content = try StoryContentRepository(content: StoryContentBundle(
            scenarios: [scenario], choiceGroups: [], events: []
        ))
        let schema = Schema([
            StoryEventProgress.self, StoryPlaybackProgress.self,
            StoryProfileValue.self, StoryMemoryUnlock.self,
        ])
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
        retainedContainers.append(container)
        let player = StoryPlayer(
            scenario: scenario,
            playbackKey: "transition-test",
            contentRepository: content,
            stateRepository: StoryStateRepository(context: container.mainContext),
            sleep: { milliseconds in
                probe.sleeps.append((milliseconds, probe.snapshot()))
                if probe.player?.sceneTransition?.phase == .covering {
                    await probe.coverGate?.wait()
                }
                probe.uptime += Double(milliseconds) / 1_000
                await Task.yield()
            },
            preloadSceneAssets: { assetIDs in
                probe.requestedAssetIDs.formUnion(assetIDs)
                await probe.assetGate?.wait()
            },
            transitionFrameBarrier: { probe.barriers.append(probe.snapshot()) },
            transitionUptime: { probe.uptime }
        )
        probe.player = player
        return player
    }

    private func eventually(_ predicate: @MainActor () -> Bool) async -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !predicate(), ProcessInfo.processInfo.systemUptime < deadline {
            try? await Task<Never, Never>.sleep(nanoseconds: 1_000_000)
        }
        return predicate()
    }
}

@MainActor
private final class TransitionProbe {
    struct Snapshot {
        let phase: StorySceneTransitionState.Phase?
        let nodeID: String?
        let background: String?
        let portrait: String?
        let isWaitingForAssets: Bool
    }

    weak var player: StoryPlayer?
    var uptime: TimeInterval = 100
    var sleeps: [(milliseconds: UInt64, snapshot: Snapshot)] = []
    var barriers: [Snapshot] = []
    var requestedAssetIDs = Set<String>()
    var coverGate: TransitionGate?
    var assetGate: TransitionGate?

    func snapshot() -> Snapshot {
        Snapshot(
            phase: player?.sceneTransition?.phase,
            nodeID: player?.currentNode?.nodeId,
            background: player?.backgroundAssetID,
            portrait: player?.portraitAssetID,
            isWaitingForAssets: player?.sceneTransition?.isWaitingForAssets ?? false
        )
    }
}

@MainActor
private final class TransitionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    var isWaiting: Bool { continuation != nil }

    func wait() async {
        guard !isReleased else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        isReleased = true
        continuation?.resume()
        continuation = nil
    }
}
