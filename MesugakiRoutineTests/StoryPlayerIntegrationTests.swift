import Foundation
import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class StoryPlayerIntegrationTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
    private var retainedContainers: [ModelContainer] = []

    private final class SoundEffectProbe: StorySoundEffectAudioPlayer {
        var volume: Float = 1
        var numberOfLoops = 0
        var currentTime: TimeInterval = 0
        var isPlaying = false
        var stopCount = 0
        func prepareToPlay() -> Bool { true }
        func play() -> Bool { isPlaying = true; return true }
        func stop() { isPlaying = false; stopCount += 1 }
    }

    func testEpisodeThreeStopsOneShotTypingAtSend() async throws {
        let repository = try makeGeneratedContentRepository()
        let original = try XCTUnwrap(repository.scenario(id: "middle_001_3"))
        let start = try XCTUnwrap(original.nodes.firstIndex { $0.nodeId == "middle_001_3_061" })
        let end = try XCTUnwrap(original.nodes.firstIndex { $0.text == "送信。" })
        let scenario = StoryScenario(scenarioId: "typing_stop", scenarioType: .middleEvent,
                                     nodes: Array(original.nodes[start...end]))
        let content = try StoryContentRepository(content: StoryContentBundle(
            scenarios: [scenario], choiceGroups: [], events: []
        ))
        let state = try makeStateRepository()
        let audio = SoundEffectProbe()
        let playback = StorySoundEffectPlaybackController(
            makePlayer: { _ in audio }, configureAudioSession: {}
        )
        var waits: [UInt64] = []
        var player: StoryPlayer!
        player = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                            contentRepository: content, stateRepository: state, sleep: { milliseconds in
            waits.append(milliseconds)
            playback.play(player.consumePendingSoundEffects())
            XCTAssertTrue(audio.isPlaying, "The long one-shot should be playing during the wait")
            XCTAssertEqual(audio.numberOfLoops, 0)
            XCTAssertEqual(audio.volume, 0.2)
        })
        await player.start()
        await player.advance()
        XCTAssertEqual(waits, [1_500])
        XCTAssertEqual(player.currentNode?.text, "送信。")
        let events = player.consumePendingSoundEffects()
        XCTAssertEqual(events, [.stop(assetID: "se_keyboard_typing")])
        playback.play(events)
        XCTAssertFalse(audio.isPlaying, "Stop must interrupt the one-shot, not wait for the file to finish")
        XCTAssertEqual(audio.stopCount, 1)
        XCTAssertTrue(player.consumePendingSoundEffects().isEmpty)

        let resumed = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                                 contentRepository: content, stateRepository: state)
        await resumed.start()
        XCTAssertEqual(resumed.currentNode?.text, "送信。")
        XCTAssertTrue(resumed.consumePendingSoundEffects().isEmpty, "Do not replay transient audio on resume")
    }

    func testSoundEffectStopOnlyInterruptsMatchingOverlappingOneShots() {
        var created: [SoundEffectProbe] = []
        let playback = StorySoundEffectPlaybackController(makePlayer: { _ in
            let audio = SoundEffectProbe()
            created.append(audio)
            return audio
        }, configureAudioSession: {})
        playback.play([
            .play(.init(assetID: "typing", volume: 0.2)),
            .play(.init(assetID: "other", volume: 1)),
            .play(.init(assetID: "typing", volume: 0.2)),
        ])
        playback.play([.stop(assetID: "typing"), .stop(assetID: "typing"), .stop(assetID: "missing")])
        XCTAssertEqual(created.map(\.isPlaying), [false, true, false])
        XCTAssertEqual(created.map(\.stopCount), [1, 0, 1])
        playback.stop()
        XCTAssertTrue(created.allSatisfy { !$0.isPlaying })
    }

    func testSoundEffectPlayStopPlayKeepsOrderWithinOneBatch() {
        var created: [SoundEffectProbe] = []
        let playback = StorySoundEffectPlaybackController(makePlayer: { _ in
            let audio = SoundEffectProbe()
            created.append(audio)
            return audio
        }, configureAudioSession: {})
        playback.play([
            .play(.init(assetID: "typing", volume: 0.2)),
            .stop(assetID: "typing"),
            .play(.init(assetID: "typing", volume: 0.2)),
        ])
        XCTAssertEqual(created.map(\.isPlaying), [false, true])
        playback.play([.stop(assetID: "typing")])
        XCTAssertEqual(created.map(\.stopCount), [1, 1])
    }

    func testSoundEffectStopStillRunsAfterAudioSessionFailure() {
        var failSession = false
        let audio = SoundEffectProbe()
        let playback = StorySoundEffectPlaybackController(makePlayer: { _ in audio }, configureAudioSession: {
            if failSession { throw NSError(domain: "audio-test", code: 1) }
        })
        playback.play([.play(.init(assetID: "typing", volume: 0.2))])
        failSession = true
        playback.play([.play(.init(assetID: "other", volume: 1)), .stop(assetID: "typing")])
        XCTAssertFalse(audio.isPlaying)
        XCTAssertEqual(audio.stopCount, 1)
    }

    func testSoundEffectLoopAndOneShotStopPathsRemainIndependent() {
        var created: [SoundEffectProbe] = []
        let playback = StorySoundEffectPlaybackController(makePlayer: { _ in
            let audio = SoundEffectProbe()
            created.append(audio)
            return audio
        }, configureAudioSession: {})
        let loop = StorySoundEffectPlayback(assetID: "typing", volume: 0.2, loop: true)
        playback.synchronizeLooping(with: ["typing": loop])
        playback.play([.play(.init(assetID: "typing", volume: 0.2))])
        XCTAssertEqual(created.map(\.numberOfLoops), [-1, 0])
        playback.play([.stop(assetID: "typing")])
        playback.synchronizeLooping(with: [:])
        XCTAssertEqual(created.map(\.isPlaying), [false, false])
        XCTAssertEqual(created.map(\.stopCount), [1, 1])

        // SwiftUI may synchronize a restarted loop before draining an older stop event.
        playback.synchronizeLooping(with: ["typing": loop])
        playback.play([.stop(assetID: "typing")])
        XCTAssertTrue(created.last!.isPlaying)
        playback.stop()
        XCTAssertFalse(created.last!.isPlaying)
    }

    func testChatToADVWaitsOneSecondWithSentReplyBeforeApplyingScene() async throws {
        for usesCommand in [false, true] {
            let scenario = StoryScenario(scenarioId: "chat_exit_\(usesCommand)", scenarioType: .middleEvent, nodes: [
                StoryNode(nodeId: "reply", lineOrder: 1, speaker: "protagonist", messageType: .text,
                          text: "わかった", screenMode: .chat, command: "scene_change"),
                StoryNode(nodeId: "adv", lineOrder: 2, speaker: "narrator", messageType: .text,
                          text: "翌日。", background: "bg_next",
                          screenMode: usesCommand ? nil : .adv,
                          command: usesCommand ? "scene_change" : nil,
                          commandArgs: usesCommand ? .object(["screen": .string("adv")]) : nil),
            ])
            let repository = try StoryContentRepository(content: StoryContentBundle(
                scenarios: [scenario], choiceGroups: [], events: []
            ))
            var waits: [UInt64] = []
            var player: StoryPlayer!
            player = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                                contentRepository: repository, stateRepository: try makeStateRepository(), sleep: { milliseconds in
                waits.append(milliseconds)
                XCTAssertEqual(player.currentMode, .chat)
                XCTAssertEqual(player.currentNode?.nodeId, "reply")
                XCTAssertTrue(player.isWaitingForChatExit)
                XCTAssertNil(player.backgroundAssetID, "Next scene must not appear before the pause")
                XCTAssertEqual(player.visibleChatNodes.last?.text, "わかった")
                XCTAssertEqual(player.visibleLogNodes.last?.nodeId, "reply")
                // A second send while waiting must not advance or add another wait.
                await player.advance()
            })
            await player.start()
            XCTAssertTrue(waits.isEmpty)
            await player.advance()
            XCTAssertEqual(waits, [1_000])
            XCTAssertEqual(player.currentMode, .adv)
            XCTAssertEqual(player.currentNode?.nodeId, "adv")
            XCTAssertEqual(player.backgroundAssetID, "bg_next")
            XCTAssertFalse(player.isWaitingForChatExit)
        }
    }

    func testClosingDuringChatExitWaitDoesNotRevealADV() async throws {
        let scenario = StoryScenario(scenarioId: "cancel_chat_exit", scenarioType: .middleEvent, nodes: [
            StoryNode(nodeId: "reply", lineOrder: 1, speaker: "protagonist", messageType: .text,
                      text: "わかった", screenMode: .chat, command: "scene_change"),
            StoryNode(nodeId: "adv", lineOrder: 2, speaker: "narrator", messageType: .text,
                      text: "翌日。", screenMode: .adv),
        ])
        let repository = try StoryContentRepository(content: StoryContentBundle(
            scenarios: [scenario], choiceGroups: [], events: []
        ))
        var player: StoryPlayer!
        player = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                            contentRepository: repository, stateRepository: try makeStateRepository(), sleep: { _ in
            player.close()
        })
        await player.start()
        await player.advance()
        XCTAssertEqual(player.currentMode, .chat)
        XCTAssertFalse(player.isWaitingForChatExit)
        XCTAssertNil(player.recoverableError)
    }

    func testOtherModeTransitionsDoNotAddChatExitPause() async throws {
        for target: StoryScreenMode in [.chat, .adv] {
            let initial: StoryScreenMode = target == .adv ? .adv : .chat
            let scenario = StoryScenario(scenarioId: "no_exit_\(target.rawValue)", scenarioType: .middleEvent, nodes: [
                StoryNode(nodeId: "first", lineOrder: 1, speaker: "protagonist", messageType: .text,
                          text: "一言目", screenMode: initial, command: "scene_change"),
                StoryNode(nodeId: "next", lineOrder: 2, speaker: "rio", messageType: .text,
                          text: "次の一言", screenMode: .chat, command: "scene_change"),
            ])
            let repository = try StoryContentRepository(content: StoryContentBundle(
                scenarios: [scenario], choiceGroups: [], events: []
            ))
            var waits: [UInt64] = []
            let player = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                                    contentRepository: repository, stateRepository: try makeStateRepository(), sleep: { waits.append($0) })
            await player.start()
            await player.advance()
            XCTAssertTrue(waits.isEmpty)
            XCTAssertEqual(player.currentMode, .chat)
        }
    }

    func testFullscreenNarrationPagesKeepChatAndLogThenCompleteOnAdvance() async throws {
        let nodes = [
            StoryNode(nodeId: "chat", lineOrder: 1, speaker: "rio", messageType: .text,
                      text: "ざこざこおにいさん♡", screenMode: .chat, command: "scene_change"),
            StoryNode(nodeId: "page1", lineOrder: 2, speaker: "narrator", messageType: .text,
                      text: "それが。", screenMode: .chat, uiVariant: .fullscreenNarration),
            StoryNode(nodeId: "page2", lineOrder: 3, speaker: "narrator", messageType: .text,
                      text: "莉央との最初の約束だった。", screenMode: .chat, uiVariant: .fullscreenNarration),
        ]
        let scenario = StoryScenario(scenarioId: "fullscreen_test", scenarioType: .middleEvent, nodes: nodes)
        let repository = try StoryContentRepository(content: StoryContentBundle(
            scenarios: [scenario], choiceGroups: [], events: []
        ))
        let player = makePlayer(scenario: scenario, playbackKey: "fullscreen_test",
                                contentRepository: repository, stateRepository: try makeStateRepository())
        await player.start()
        player.markCurrentNodePresented()
        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "page1")
        XCTAssertEqual(player.currentMode, .chat)
        XCTAssertFalse(player.visibleLogNodes.contains { $0.nodeId == "page1" })
        player.markCurrentNodePresented()
        XCTAssertTrue(player.visibleLogNodes.contains { $0.nodeId == "page1" })
        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "page2")
        XCTAssertFalse(player.isCompleted)
        XCTAssertEqual(player.visibleChatNodes.filter {
            !EventChatSystemPresentationPolicy.omitsFromChatHistory(node: $0, scenarioType: .middleEvent)
        }.map(\.nodeId), ["chat"])
        player.markCurrentNodePresented()
        await player.advance()
        XCTAssertTrue(player.isCompleted)
        XCTAssertEqual(player.visibleLogNodes.map(\.nodeId), nodes.map(\.nodeId))
        XCTAssertNil(player.recoverableError)
    }

    func testChatOnlySmallEventsStartWithoutSceneChangeDiagnostic() async throws {
        let stateRepository = try makeStateRepository()
        // Both CMS encodings must work even when the current catalog has no small events.
        for usesCommandArgument in [false, true] {
            let scenario = StoryScenario(
                scenarioId: "chat_only_\(usesCommandArgument)", scenarioType: .smallEvent,
                nodes: [
                    StoryNode(nodeId: "scene", lineOrder: 1, speaker: "system", messageType: .action,
                              screenMode: usesCommandArgument ? nil : .chat, uiVariant: .sceneTransition,
                              command: "scene_change", commandArgs: usesCommandArgument
                                ? .object(["screen": .string("chat")]) : nil),
                    StoryNode(nodeId: "message", lineOrder: 2, speaker: "rio", messageType: .text,
                              text: "おはよう", screenMode: .chat, uiVariant: .dialogue),
                ]
            )
            let event = makeTestEvent(for: scenario, type: .small)
            let contentRepository = try makeTestContentRepository(scenario: scenario, event: event)
            let player = makePlayer(
                scenario: scenario, event: event, playbackKey: "integration:scene:\(event.eventId)",
                contentRepository: contentRepository, stateRepository: stateRepository
            )
            await player.start()
            XCTAssertEqual(player.currentMode, .chat, scenario.scenarioId)
            XCTAssertEqual(player.currentNode?.nodeId, "message", scenario.scenarioId)
            XCTAssertNil(player.recoverableError, scenario.scenarioId)
        }
    }

    func testBundledMainStoriesTraverseAndPersistCompletion() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()
        let events = contentRepository.events
            .filter { $0.storyCategory == .main }
            .sorted { ($0.episodeOrder ?? .max) < ($1.episodeOrder ?? .max) }

        XCTAssertFalse(events.isEmpty, "The bundled main-story catalog must not be empty")
        XCTAssertTrue(events.contains { $0.eventType != .prologue }, "Include released episodes, not only the prologue")

        for event in events {
            let scenario = try XCTUnwrap(
                contentRepository.scenario(id: event.entryScenarioId),
                "Missing scenario for \(event.eventId)"
            )
            let playbackKey = "integration:event:\(event.eventId)"
            try stateRepository.markUnlocked(eventId: event.eventId, at: fixedNow)
            let player = makePlayer(
                scenario: scenario,
                event: event,
                playbackKey: playbackKey,
                contentRepository: contentRepository,
                stateRepository: stateRepository
            )

            await player.start()
            try await driveStartedPlayerToCompletion(
                player,
                safetyLimit: scenario.nodes.count * 3
            ) { player in
                XCTAssertNil(player.recoverableError, event.eventId)
            }

            let checkpoint = try XCTUnwrap(stateRepository.checkpoint(for: playbackKey))
            let expectedNodeIDs = scenario.nodes
                .sorted { $0.lineOrder < $1.lineOrder }
                .map(\.nodeId)
            XCTAssertTrue(checkpoint.isCompleted, event.eventId)
            XCTAssertNil(checkpoint.currentNodeId, event.eventId)
            XCTAssertEqual(checkpoint.visitedNodeIds, expectedNodeIDs, event.eventId)

            let progress = try XCTUnwrap(
                stateRepository.eventProgress(for: event.eventId),
                event.eventId
            )
            XCTAssertTrue(progress.isUnlocked, event.eventId)
            XCTAssertTrue(progress.isRead, event.eventId)
            XCTAssertTrue(progress.isCompleted, event.eventId)
            XCTAssertEqual(progress.completionCount, 1, event.eventId)
        }
    }

    func testAudioMessageIsPresentedAndRetainedInChatAfterAdvancing() async throws {
        let scenario = StoryScenario(scenarioId: "audio_message", scenarioType: .smallEvent, nodes: [
            StoryNode(nodeId: "audio", lineOrder: 1, speaker: "rio", messageType: .action,
                      assetId: "test_recording", screenMode: .chat, uiVariant: .audioMessage,
                      command: "play_audio"),
            StoryNode(nodeId: "after_audio", lineOrder: 2, speaker: "rio", messageType: .text,
                      text: "聞こえた？", screenMode: .chat, uiVariant: .dialogue),
        ])
        let content = try makeTestContentRepository(scenario: scenario)
        let state = try makeStateRepository()
        let player = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                                contentRepository: content, stateRepository: state)

        await player.start()
        XCTAssertEqual(player.currentNode?.nodeId, "audio")
        XCTAssertEqual(player.currentNode?.uiVariant, .audioMessage)
        XCTAssertEqual(player.currentNode?.assetId, "test_recording")
        XCTAssertEqual(player.activeAudioAssetID, "test_recording")
        XCTAssertFalse(player.isCompleted, "An audio message must wait for the reader")

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "after_audio")
        XCTAssertEqual(player.visibleChatNodes.map(\.nodeId), ["audio", "after_audio"])
        XCTAssertEqual(player.visibleChatNodes.first?.assetId, "test_recording")
        await player.advance()
        XCTAssertTrue(player.isCompleted)
        XCTAssertEqual(player.visibleChatNodes.map(\.nodeId), ["audio", "after_audio"])
        XCTAssertNil(player.recoverableError)
    }

    func testADVToChatTransitionAndCGVisibilityUnlockOnlyOnCompletion() async throws {
        let largeScenario = StoryScenario(scenarioId: "cg_transition", scenarioType: .largeEvent, nodes: [
            StoryNode(nodeId: "scene", lineOrder: 1, speaker: "system", messageType: .action,
                      background: "test_background", screenMode: .adv, uiVariant: .sceneTransition,
                      command: "scene_change"),
            StoryNode(nodeId: "intro", lineOrder: 2, speaker: "narrator", messageType: .text,
                      text: "導入", screenMode: .adv, uiVariant: .narration),
            // A quoted line with a legacy row-level chat value must remain in ADV.
            StoryNode(nodeId: "quoted", lineOrder: 3, speaker: "rio", messageType: .text,
                      text: "『人生再建プログラム』", screenMode: .chat, uiVariant: .dialogue),
            StoryNode(nodeId: "show_cg", lineOrder: 4, speaker: "system", messageType: .action,
                      assetId: "test_cg", screenMode: .adv, uiVariant: .cg, command: "show_cg"),
            StoryNode(nodeId: "cg_dialogue", lineOrder: 5, speaker: "rio", messageType: .text,
                      text: "スチルのセリフ", screenMode: .adv, uiVariant: .dialogue),
            StoryNode(nodeId: "hide_cg", lineOrder: 6, speaker: "system", messageType: .action,
                      screenMode: .adv, uiVariant: .cg, command: "hide_cg"),
            StoryNode(nodeId: "after_cg", lineOrder: 7, speaker: "rio", messageType: .text,
                      text: "通常の画面", screenMode: .adv, uiVariant: .dialogue),
            StoryNode(nodeId: "chat_scene", lineOrder: 8, speaker: "system", messageType: .action,
                      screenMode: .chat, uiVariant: .sceneTransition, command: "scene_change"),
            StoryNode(nodeId: "chat_message", lineOrder: 9, speaker: "rio", messageType: .text,
                      text: "またね", screenMode: .chat, uiVariant: .dialogue),
        ])
        let largeEvent = makeTestEvent(for: largeScenario, type: .large)
        let contentRepository = try makeTestContentRepository(scenario: largeScenario, event: largeEvent)
        let stateRepository = try makeStateRepository()
        let largePlayer = makePlayer(
            scenario: largeScenario,
            event: largeEvent,
            playbackKey: "integration:modes:cg_transition",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        var largeModes: [StoryScreenMode] = []
        var quotedLineModes: [StoryScreenMode] = []
        var didShowCG = false
        var didHideCGAfterShowing = false

        await largePlayer.start()
        XCTAssertEqual(largePlayer.currentNode?.nodeId, "intro")
        XCTAssertEqual(largePlayer.currentNode?.uiVariant, .narration)
        XCTAssertEqual(largePlayer.backgroundAssetID, "test_background")
        XCTAssertEqual(
            try stateRepository.checkpoint(for: "integration:modes:cg_transition")?.visitedNodeIds,
            ["scene", "intro"]
        )
        try await driveStartedPlayerToCompletion(
            largePlayer,
            safetyLimit: largeScenario.nodes.count * 3
        ) { player in
            largeModes.append(player.currentMode)
            XCTAssertNil(player.recoverableError)
            if player.currentNode?.nodeId == "quoted" {
                XCTAssertEqual(player.currentNode?.storyDisplayText, "『人生再建プログラム』")
                quotedLineModes.append(player.currentMode)
            }
            if !player.isCompleted {
                XCTAssertNil(
                    try stateRepository.memoryUnlock(for: "test_cg"),
                    "A traversed CG must stay locked until normal completion"
                )
            }
            if player.cgAssetID == "test_cg" {
                didShowCG = true
            } else if player.currentNode?.nodeId == "after_cg", didShowCG {
                didHideCGAfterShowing = true
            }
        }

        XCTAssertEqual(compressed(largeModes), [.adv, .chat])
        XCTAssertFalse(quotedLineModes.isEmpty)
        XCTAssertTrue(quotedLineModes.allSatisfy { $0 == .adv })
        XCTAssertTrue(didShowCG)
        XCTAssertTrue(didHideCGAfterShowing)
        let unlockedCG = try XCTUnwrap(
            stateRepository.memoryUnlock(for: "test_cg")
        )
        XCTAssertEqual(unlockedCG.sourceEventId, largeEvent.eventId)
        XCTAssertEqual(unlockedCG.sourceScenarioId, largeScenario.scenarioId)
    }

    func testChatCallChatTransitionWithImageModalAndTypingWait() async throws {
        let callScenario = StoryScenario(scenarioId: "call_transition", scenarioType: .smallEvent, nodes: [
            StoryNode(nodeId: "image", lineOrder: 1, speaker: "rio", messageType: .image,
                      assetId: "test_image", screenMode: .chat, uiVariant: .imageMessage),
            StoryNode(nodeId: "typing", lineOrder: 2, speaker: "system", messageType: .action,
                      screenMode: .chat, uiVariant: .typing, command: "typing_show"),
            StoryNode(nodeId: "wait", lineOrder: 3, speaker: "system", messageType: .action,
                      screenMode: .chat, uiVariant: .typing, command: "wait",
                      commandArgs: .object(["duration_ms": .number(300)])),
            StoryNode(nodeId: "reply", lineOrder: 4, speaker: "rio", messageType: .text,
                      text: "電話してもいい？", screenMode: .chat, uiVariant: .dialogue),
            StoryNode(nodeId: "incoming", lineOrder: 5, speaker: "rio", messageType: .action,
                      screenMode: .call, uiVariant: .incomingCall, command: "call_start"),
            StoryNode(nodeId: "connected", lineOrder: 6, speaker: "rio", messageType: .action,
                      screenMode: .call, uiVariant: .callConnected, command: "call_connected"),
            StoryNode(nodeId: "ended", lineOrder: 7, speaker: "rio", messageType: .action,
                      screenMode: .call, uiVariant: .callEnd, command: "call_end"),
            StoryNode(nodeId: "chat_scene", lineOrder: 8, speaker: "system", messageType: .action,
                      screenMode: .chat, uiVariant: .sceneTransition, command: "scene_change"),
            StoryNode(nodeId: "modal", lineOrder: 9, speaker: "system", messageType: .text,
                      text: "確認", screenMode: .chat, uiVariant: .modal, command: "show_modal"),
            StoryNode(nodeId: "after_modal", lineOrder: 10, speaker: "rio", messageType: .text,
                      text: "また明日", screenMode: .chat, uiVariant: .dialogue),
        ])
        let callEvent = makeTestEvent(for: callScenario, type: .small)
        let contentRepository = try makeTestContentRepository(scenario: callScenario, event: callEvent)
        let stateRepository = try makeStateRepository()
        let sleepProbe = StoryPlayerSleepProbe()
        let callPlayer = makePlayer(
            scenario: callScenario,
            event: callEvent,
            playbackKey: "integration:modes:call_transition",
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            sleep: { milliseconds in
                sleepProbe.record(milliseconds: milliseconds)
            }
        )
        sleepProbe.player = callPlayer
        var callModes: [StoryScreenMode] = []
        var observedCallNodeIDs: [String] = []
        var callStates: [StoryCallPresentationState?] = []
        var didPresentImageMessage = false
        var didPresentModal = false

        await callPlayer.start()
        try await driveStartedPlayerToCompletion(
            callPlayer,
            safetyLimit: callScenario.nodes.count * 3
        ) { player in
            callModes.append(player.currentMode)
            XCTAssertNil(player.recoverableError)
            if let nodeID = player.currentNode?.nodeId {
                observedCallNodeIDs.append(nodeID)
            }
            if player.currentMode == .call { callStates.append(player.callState) }
            if player.currentNode?.nodeId == "image" {
                didPresentImageMessage =
                    player.currentNode?.uiVariant == .imageMessage
                    && player.currentNode?.assetId == "test_image"
            }
            if player.currentNode?.nodeId == "reply" {
                XCTAssertFalse(player.isTyping, "A delivered message clears the typing indicator")
            }
            if player.currentNode?.nodeId == "modal" {
                didPresentModal = player.isModalPresented
            }
            if player.currentNode?.nodeId == "after_modal" { XCTAssertFalse(player.isModalPresented) }
        }

        XCTAssertEqual(compressed(callModes), [.chat, .call, .chat])
        XCTAssertEqual(callStates, [.starting, .connected, .ended])
        XCTAssertEqual(observedCallNodeIDs, ["image", "reply", "incoming", "connected", "ended", "modal", "after_modal"])
        XCTAssertTrue(didPresentImageMessage)
        XCTAssertTrue(didPresentModal)
        XCTAssertTrue(sleepProbe.sawTypingDuringWait)
    }

    func testBundledMiddleAndLargeEventsDoNotContainMemoTitleCards() throws {
        let contentRepository = try makeGeneratedContentRepository()
        let scenarios = contentRepository.events
            .filter { $0.eventType == .middle || $0.eventType == .large }
            .map { contentRepository.scenario(id: $0.entryScenarioId) }
        XCTAssertFalse(scenarios.isEmpty)
        for scenario in scenarios {
            let scenario = try XCTUnwrap(scenario)
            XCTAssertFalse(scenario.nodes.contains { $0.uiVariant == .titleCard }, scenario.scenarioId)
        }
    }

    func testMiddleEventAppliesEmptySystemTransitionsWithoutPresentingThem() async throws {
        let scenario = StoryScenario(scenarioId: "hidden_system", scenarioType: .middleEvent, nodes: [
            StoryNode(nodeId: "scene", lineOrder: 1, speaker: "system", messageType: .action,
                      text: "", background: "test_station", screenMode: .adv,
                      uiVariant: .sceneTransition, command: "scene_change"),
            StoryNode(nodeId: "portrait", lineOrder: 2, speaker: "system", messageType: .action,
                      text: "", portrait: "test_rio", screenMode: .adv,
                      uiVariant: .sceneTransition, command: "show_portrait"),
            StoryNode(nodeId: "narration", lineOrder: 3, speaker: "narrator", messageType: .text,
                      text: "駅前に到着した。", screenMode: .adv, uiVariant: .narration),
        ])
        let event = makeTestEvent(for: scenario, type: .middle)
        let contentRepository = try makeTestContentRepository(scenario: scenario, event: event)
        let stateRepository = try makeStateRepository()
        let playbackKey = "integration:hidden-system"
        let player = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()

        XCTAssertEqual(player.currentNode?.nodeId, "narration")
        XCTAssertEqual(player.currentNode?.uiVariant, .narration)
        XCTAssertEqual(player.backgroundAssetID, "test_station")
        XCTAssertEqual(player.portraitAssetID, "test_rio")
        XCTAssertEqual(player.visibleLogNodes.map(\.nodeId), ["narration"])
        XCTAssertNil(player.recoverableError)
        XCTAssertEqual(
            try stateRepository.checkpoint(for: playbackKey)?.visitedNodeIds,
            ["scene", "portrait", "narration"]
        )
    }

    func testClearBackgroundCommandDiscardsTheCurrentBackground() async throws {
        let scenario = StoryScenario(
            scenarioId: "clear_background",
            scenarioType: .smallEvent,
            nodes: [
                StoryNode(
                    nodeId: "set_background",
                    lineOrder: 1,
                    speaker: "system",
                    messageType: .action,
                    background: "bg_protagonist_living_room",
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "scene_change"
                ),
                StoryNode(
                    nodeId: "before_clear",
                    lineOrder: 2,
                    speaker: "narrator",
                    messageType: .text,
                    text: "背景あり",
                    screenMode: .adv,
                    uiVariant: .narration
                ),
                StoryNode(
                    nodeId: "clear_background",
                    lineOrder: 3,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "clear_background"
                ),
                StoryNode(
                    nodeId: "hide_portrait",
                    lineOrder: 4,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "hide_portrait"
                ),
                StoryNode(
                    nodeId: "after_clear",
                    lineOrder: 5,
                    speaker: "narrator",
                    messageType: .text,
                    text: "黒背景",
                    screenMode: .adv,
                    uiVariant: .narration
                ),
                StoryNode(
                    nodeId: "next_black_line",
                    lineOrder: 6,
                    speaker: "narrator",
                    messageType: .text,
                    text: "次の行",
                    screenMode: .adv,
                    uiVariant: .narration
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(
                scenarios: [scenario],
                choiceGroups: [],
                events: []
            )
        )
        let stateRepository = try makeStateRepository()
        let playbackKey = "integration:clear_background"
        let player = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()

        XCTAssertEqual(player.currentNode?.nodeId, "before_clear")
        XCTAssertEqual(player.backgroundAssetID, "bg_protagonist_living_room")

        await player.advance()

        XCTAssertEqual(player.currentNode?.nodeId, "after_clear")
        XCTAssertNil(player.backgroundAssetID)
        XCTAssertTrue(player.shouldDelayCurrentADVText)
        XCTAssertEqual(
            try stateRepository.checkpoint(for: playbackKey)?.visitedNodeIds,
            ["set_background", "before_clear", "clear_background", "hide_portrait", "after_clear"]
        )

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "next_black_line")
        XCTAssertFalse(player.shouldDelayCurrentADVText)
    }

    func testExplicitWaitAfterBlackoutPreventsAnExtraTextDelay() async throws {
        let scenario = StoryScenario(
            scenarioId: "blackout_with_wait",
            scenarioType: .prologue,
            nodes: [
                StoryNode(
                    nodeId: "opening",
                    lineOrder: 1,
                    speaker: "rio",
                    messageType: .text,
                    text: "おわり〜",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
                StoryNode(
                    nodeId: "clear_background",
                    lineOrder: 2,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "clear_background"
                ),
                StoryNode(
                    nodeId: "hide_portrait",
                    lineOrder: 3,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "hide_portrait"
                ),
                StoryNode(
                    nodeId: "blackout_wait",
                    lineOrder: 4,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "wait",
                    commandArgs: .object(["duration_ms": .number(300)])
                ),
                StoryNode(
                    nodeId: "after_wait",
                    lineOrder: 5,
                    speaker: "narrator",
                    messageType: .text,
                    text: "数週間前。",
                    screenMode: .adv,
                    uiVariant: .narration
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(scenarios: [scenario], choiceGroups: [], events: [])
        )
        let stateRepository = try makeStateRepository()
        var waits: [UInt64] = []
        let player = makePlayer(
            scenario: scenario,
            playbackKey: "integration:blackout_with_wait",
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            sleep: { waits.append($0) }
        )

        await player.start()
        await player.advance()

        XCTAssertEqual(waits, [300])
        XCTAssertEqual(player.currentNode?.nodeId, "after_wait")
        XCTAssertFalse(player.shouldDelayCurrentADVText)
    }

    func testPortraitHesitationUsesDefaultAndExplicitDurationsThenAdvancesAutomatically() async throws {
        let scenario = StoryScenario(
            scenarioId: "portrait_hesitation_durations",
            scenarioType: .prologue,
            nodes: [
                StoryNode(
                    nodeId: "before_hesitation",
                    lineOrder: 1,
                    speaker: "rio",
                    messageType: .text,
                    text: "えっと……",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
                StoryNode(
                    nodeId: "default_hesitation",
                    lineOrder: 2,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "portrait_hesitate"
                ),
                StoryNode(
                    nodeId: "custom_hesitation",
                    lineOrder: 3,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "portrait_hesitate",
                    commandArgs: .object(["duration_ms": .number(1_800)])
                ),
                StoryNode(
                    nodeId: "after_hesitation",
                    lineOrder: 4,
                    speaker: "rio",
                    messageType: .text,
                    text: "……やっぱり言うね。",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(scenarios: [scenario], choiceGroups: [], events: [])
        )
        let stateRepository = try makeStateRepository()
        let sleepProbe = StoryPlayerHesitationSleepProbe()
        let player = makePlayer(
            scenario: scenario,
            playbackKey: "integration:portrait_hesitation_durations",
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            sleep: { sleepProbe.record(milliseconds: $0) }
        )
        sleepProbe.player = player

        await player.start()
        XCTAssertEqual(player.currentNode?.nodeId, "before_hesitation")
        XCTAssertFalse(player.isHesitating)

        await player.advance()

        XCTAssertEqual(sleepProbe.waits.map(\.milliseconds), [1_500, 1_800])
        XCTAssertEqual(
            sleepProbe.waits.map(\.nodeID),
            ["default_hesitation", "custom_hesitation"]
        )
        XCTAssertTrue(sleepProbe.waits.allSatisfy(\.isHesitating))
        XCTAssertEqual(player.currentNode?.nodeId, "after_hesitation")
        XCTAssertFalse(player.isHesitating)
        XCTAssertEqual(
            try stateRepository.checkpoint(
                for: "integration:portrait_hesitation_durations"
            )?.visitedNodeIds,
            [
                "before_hesitation",
                "default_hesitation",
                "custom_hesitation",
                "after_hesitation",
            ]
        )
    }

    func testClosingDuringPortraitHesitationClearsBubbleAndResumeSkipsCompletedWait() async throws {
        let scenario = StoryScenario(
            scenarioId: "portrait_hesitation_resume",
            scenarioType: .prologue,
            nodes: [
                StoryNode(
                    nodeId: "hesitation",
                    lineOrder: 1,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "portrait_hesitate"
                ),
                StoryNode(
                    nodeId: "after_hesitation",
                    lineOrder: 2,
                    speaker: "rio",
                    messageType: .text,
                    text: "話すね。",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(scenarios: [scenario], choiceGroups: [], events: [])
        )
        let stateRepository = try makeStateRepository()
        let sleepGate = StoryPlayerHesitationSleepGate()
        let player = makePlayer(
            scenario: scenario,
            playbackKey: "integration:portrait_hesitation_resume",
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            sleep: { milliseconds in
                sleepGate.waits.append(milliseconds)
                await sleepGate.wait()
            }
        )

        let startTask = Task { await player.start() }
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while !sleepGate.isWaiting, ProcessInfo.processInfo.systemUptime < deadline {
            try await Task<Never, Never>.sleep(nanoseconds: 1_000_000)
        }

        XCTAssertTrue(sleepGate.isWaiting)
        XCTAssertEqual(player.currentNode?.nodeId, "hesitation")
        XCTAssertTrue(player.isHesitating)
        player.close()
        XCTAssertFalse(player.isHesitating)

        sleepGate.release()
        await startTask.value
        await player.start()

        XCTAssertEqual(sleepGate.waits, [1_500])
        XCTAssertEqual(player.currentNode?.nodeId, "after_hesitation")
        XCTAssertFalse(player.isHesitating)
    }

    func testGeneratedPrologueHidesPortraitImmediatelyAfterClearingBackground() throws {
        let contentRepository = try makeGeneratedContentRepository()
        let scenario = try XCTUnwrap(contentRepository.scenario(id: "prologue_001"))
        let nodes = scenario.nodes.sorted { $0.lineOrder < $1.lineOrder }

        let narrationIndex = try XCTUnwrap(nodes.firstIndex { $0.text == "数週間前。" })
        // Assert the authored sequence, not generated IDs or the number of preceding lines.
        let transition = Array(nodes.prefix(narrationIndex).suffix(3))
        XCTAssertEqual(transition.map(\.command), ["clear_background", "hide_portrait", "wait"])
        XCTAssertTrue(transition.allSatisfy { ($0.text ?? "").isEmpty })
        let wait = try XCTUnwrap(transition.last)
        let duration = try XCTUnwrap(wait.commandArgs?["duration_ms"]?.intValue)
        XCTAssertGreaterThan(duration, 0, "The blackout must pause before the narration appears")
        XCTAssertEqual(nodes[narrationIndex].uiVariant, .narration)
    }

    func testPortraitAndBGMCommandsPersistUntilExplicitlyHiddenOrStopped() async throws {
        let scenario = StoryScenario(
            scenarioId: "presentation_commands",
            scenarioType: .prologue,
            nodes: [
                StoryNode(
                    nodeId: "play_bgm",
                    lineOrder: 1,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "play_bgm",
                    commandArgs: .object([
                        "asset_id": .string("bgm_usually"),
                        "loop": .bool(true),
                        "fade_ms": .number(1_000),
                        "volume": .number(0.8),
                    ])
                ),
                StoryNode(
                    nodeId: "show_portrait",
                    lineOrder: 2,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "show_portrait",
                    commandArgs: .object([
                        "asset_id": .string("portrait_rio_laugh"),
                    ])
                ),
                StoryNode(
                    nodeId: "with_presentation",
                    lineOrder: 3,
                    speaker: "rio",
                    messageType: .text,
                    text: "あははっ",
                    speakerName: "莉央",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
                StoryNode(
                    nodeId: "hide_portrait",
                    lineOrder: 4,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "hide_portrait"
                ),
                StoryNode(
                    nodeId: "stop_bgm",
                    lineOrder: 5,
                    speaker: "system",
                    messageType: .action,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "stop_bgm"
                ),
                StoryNode(
                    nodeId: "without_presentation",
                    lineOrder: 6,
                    speaker: "narrator",
                    messageType: .text,
                    text: "暗転",
                    speakerName: "地の文",
                    screenMode: .adv,
                    uiVariant: .narration
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(scenarios: [scenario], choiceGroups: [], events: [])
        )
        let stateRepository = try makeStateRepository()
        let player = makePlayer(
            scenario: scenario,
            playbackKey: "integration:presentation_commands",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()

        XCTAssertEqual(player.currentNode?.nodeId, "with_presentation")
        XCTAssertEqual(player.portraitAssetID, "portrait_rio_laugh")
        XCTAssertEqual(
            player.bgmPlaybackState,
            StoryBGMPlaybackState(
                assetID: "bgm_usually",
                loop: true,
                fadeMilliseconds: 1_000,
                volume: 0.8
            )
        )

        await player.advance()

        XCTAssertEqual(player.currentNode?.nodeId, "without_presentation")
        XCTAssertNil(player.portraitAssetID)
        XCTAssertNil(player.bgmPlaybackState)
        XCTAssertEqual(player.pendingBGMEvents.last, .stop(fadeMilliseconds: 1_000))
    }

    func testBGMStopPlayOrderSurvivesAutomaticTraversalAndRestoreDoesNotReplayCommands() async throws {
        let scenario = StoryScenario(scenarioId: "bgm_order", scenarioType: .prologue, nodes: [
            StoryNode(nodeId: "play", lineOrder: 1, speaker: "system", messageType: .action,
                      assetId: "music", command: "play_bgm"),
            StoryNode(nodeId: "first", lineOrder: 2, speaker: "rio", messageType: .text, text: "最初"),
            StoryNode(nodeId: "instant_stop", lineOrder: 3, speaker: "system", messageType: .action,
                      command: "stop_bgm", commandArgs: .object(["fade_ms": .number(0)])),
            StoryNode(nodeId: "replay", lineOrder: 4, speaker: "system", messageType: .action,
                      assetId: "music", command: "play_bgm"),
            StoryNode(nodeId: "second", lineOrder: 5, speaker: "rio", messageType: .text, text: "再開"),
            StoryNode(nodeId: "fade_stop", lineOrder: 6, speaker: "system", messageType: .action,
                      command: "stop_bgm", commandArgs: .object(["fade_ms": .number(1_500)])),
            StoryNode(nodeId: "last", lineOrder: 7, speaker: "rio", messageType: .text, text: "最後"),
        ])
        let content = try makeTestContentRepository(scenario: scenario)
        let state = try makeStateRepository()
        let player = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                                contentRepository: content, stateRepository: state)
        await player.start()
        let music = try XCTUnwrap(player.bgmPlaybackState)
        XCTAssertEqual(player.consumePendingBGMEvents(), [.play(music)])
        XCTAssertTrue(player.consumePendingBGMEvents().isEmpty)

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "second")
        XCTAssertEqual(player.bgmPlaybackUpdate, .init(state: music, events: [
            .stop(fadeMilliseconds: 0), .play(music),
        ]))

        let restored = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                                  contentRepository: content, stateRepository: state)
        await restored.start()
        XCTAssertEqual(restored.currentNode?.nodeId, "second")
        XCTAssertEqual(restored.bgmPlaybackState, music)
        XCTAssertTrue(restored.consumePendingBGMEvents().isEmpty)

        await restored.advance()
        XCTAssertEqual(restored.currentNode?.nodeId, "last")
        XCTAssertNil(restored.bgmPlaybackState)
        XCTAssertEqual(restored.consumePendingBGMEvents(), [.stop(fadeMilliseconds: 1_500)])
        await restored.advance()
        XCTAssertTrue(restored.isCompleted)
        XCTAssertTrue(restored.consumePendingBGMEvents().isEmpty,
                      "Completion must not override an explicit stop duration")
    }

    func testBGMFadesOutByDefaultOnCompletionAndSkip() async throws {
        for skips in [false, true] {
            let scenario = StoryScenario(scenarioId: "bgm_end_\(skips)", scenarioType: .middleEvent, nodes: [
                StoryNode(nodeId: "play", lineOrder: 1, speaker: "system", messageType: .action,
                          assetId: "music", command: "play_bgm"),
                StoryNode(nodeId: "last", lineOrder: 2, speaker: "rio", messageType: .text, text: "最後"),
            ])
            let content = try makeTestContentRepository(scenario: scenario)
            let state = try makeStateRepository()
            let player = makePlayer(scenario: scenario, playbackKey: scenario.scenarioId,
                                    contentRepository: content, stateRepository: state)
            await player.start()
            XCTAssertNotNil(player.bgmPlaybackState)
            _ = player.consumePendingBGMEvents()
            if skips {
                let didSkip = await player.skip()
                XCTAssertTrue(didSkip)
            } else {
                await player.advance()
            }
            XCTAssertTrue(player.isCompleted)
            XCTAssertNil(player.bgmPlaybackState)
            XCTAssertEqual(player.consumePendingBGMEvents(), [.stop(fadeMilliseconds: 1_000)])
        }
    }

    func testSoundEffectsPlayOncePerVisitWithoutReplayingOnCheckpointRestore() async throws {
        let scenario = StoryScenario(
            scenarioId: "sound_effect_commands",
            scenarioType: .prologue,
            nodes: [
                StoryNode(
                    nodeId: "bgm",
                    lineOrder: 1,
                    speaker: "system",
                    messageType: .action,
                    command: "play_bgm",
                    commandArgs: .object(["asset_id": .string("bgm_usually")])
                ),
                StoryNode(
                    nodeId: "first_se",
                    lineOrder: 2,
                    speaker: "system",
                    messageType: .action,
                    command: "play_se",
                    commandArgs: .object(["asset_id": .string("se_defeat")])
                ),
                StoryNode(
                    nodeId: "second_se",
                    lineOrder: 3,
                    speaker: "system",
                    messageType: .action,
                    command: "play_se",
                    commandArgs: .object([
                        "asset_id": .string("se_defeat"),
                        "volume": .number(0.4),
                    ])
                ),
                StoryNode(
                    nodeId: "first_line",
                    lineOrder: 4,
                    speaker: "rio",
                    messageType: .text,
                    text: "まだ続くよ",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
                StoryNode(
                    nodeId: "third_se",
                    lineOrder: 5,
                    speaker: "system",
                    messageType: .action,
                    command: "play_se",
                    commandArgs: .object(["asset_id": .string("se_defeat")])
                ),
                StoryNode(
                    nodeId: "second_line",
                    lineOrder: 6,
                    speaker: "rio",
                    messageType: .text,
                    text: "次の台詞",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(scenarios: [scenario], choiceGroups: [], events: [])
        )
        let stateRepository = try makeStateRepository()
        let playbackKey = "integration:sound_effect_commands"
        let player = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()

        XCTAssertEqual(player.currentNode?.nodeId, "first_line")
        XCTAssertEqual(player.bgmPlaybackState?.assetID, "bgm_usually")
        XCTAssertEqual(
            player.consumePendingSoundEffects(),
            [
                .play(StorySoundEffectPlayback(assetID: "se_defeat", volume: 1)),
                .play(StorySoundEffectPlayback(assetID: "se_defeat", volume: 0.4)),
            ]
        )
        XCTAssertTrue(player.consumePendingSoundEffects().isEmpty)

        let resumedPlayer = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await resumedPlayer.start()
        XCTAssertEqual(resumedPlayer.currentNode?.nodeId, "first_line")
        XCTAssertEqual(resumedPlayer.bgmPlaybackState?.assetID, "bgm_usually")
        XCTAssertTrue(resumedPlayer.consumePendingSoundEffects().isEmpty)

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "second_line")
        XCTAssertEqual(
            player.consumePendingSoundEffects(),
            [.play(StorySoundEffectPlayback(assetID: "se_defeat", volume: 1))]
        )
    }

    func testLoopingSoundEffectRestoresAndStopsAtTheScriptedBoundary() async throws {
        let scenario = StoryScenario(
            scenarioId: "looping_sound_effect",
            scenarioType: .middleEvent,
            nodes: [
                StoryNode(
                    nodeId: "start_loop",
                    lineOrder: 1,
                    speaker: "system",
                    messageType: .action,
                    command: "play_se",
                    commandArgs: .object([
                        "action": .string("play"),
                        "asset_id": .string("se_keyboard_typing"),
                        "loop": .bool(true),
                    ])
                ),
                StoryNode(
                    nodeId: "first_line",
                    lineOrder: 2,
                    speaker: "rio",
                    messageType: .text,
                    text: "入力中",
                    screenMode: .chat,
                    uiVariant: .dialogue
                ),
                StoryNode(
                    nodeId: "stop_loop",
                    lineOrder: 3,
                    speaker: "system",
                    messageType: .action,
                    command: "play_se",
                    commandArgs: .object([
                        "action": .string("stop"),
                        "asset_id": .string("se_keyboard_typing"),
                    ])
                ),
                StoryNode(
                    nodeId: "second_line",
                    lineOrder: 4,
                    speaker: "rio",
                    messageType: .text,
                    text: "入力終了",
                    screenMode: .chat,
                    uiVariant: .dialogue
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(scenarios: [scenario], choiceGroups: [], events: [])
        )
        let stateRepository = try makeStateRepository()
        let playbackKey = "integration:looping_sound_effect"
        let player = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()
        XCTAssertEqual(player.currentNode?.nodeId, "first_line")
        XCTAssertEqual(
            player.loopingSoundEffects["se_keyboard_typing"],
            StorySoundEffectPlayback(assetID: "se_keyboard_typing", volume: 1, loop: true)
        )
        XCTAssertTrue(player.consumePendingSoundEffects().isEmpty)

        let resumedPlayer = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await resumedPlayer.start()
        XCTAssertEqual(resumedPlayer.currentNode?.nodeId, "first_line")
        XCTAssertEqual(
            resumedPlayer.loopingSoundEffects["se_keyboard_typing"],
            StorySoundEffectPlayback(assetID: "se_keyboard_typing", volume: 1, loop: true)
        )

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "second_line")
        XCTAssertTrue(player.loopingSoundEffects.isEmpty)
        XCTAssertEqual(player.consumePendingSoundEffects(), [.stop(assetID: "se_keyboard_typing")])
    }

    func testRealDailyChoiceTargetsExistingBranchAndPersistsValue() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()

        let branchingScenario = try XCTUnwrap(contentRepository.scenario(id: "daily_q003"))
        let branchingPlayer = makePlayer(
            scenario: branchingScenario,
            playbackKey: "integration:daily:q003",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await branchingPlayer.start()
        try await advanceUntilChoice(
            "choice_solo_movie",
            player: branchingPlayer,
            safetyLimit: branchingScenario.nodes.count * 2
        )
        let branchingChoice = try XCTUnwrap(branchingPlayer.availableChoices.first)
        XCTAssertEqual(branchingChoice.nextNodeId, "daily_q003_can_001")

        await branchingPlayer.selectChoice(branchingChoice)

        XCTAssertEqual(branchingPlayer.currentNode?.nodeId, "daily_q003_can_001")
        XCTAssertEqual(branchingChoice.saveKey, "soloMovie")
        XCTAssertEqual(try stateRepository.profileValue(for: "soloMovie"), "can")
        XCTAssertNil(branchingPlayer.recoverableError)
        try await driveStartedPlayerToCompletion(
            branchingPlayer,
            safetyLimit: branchingScenario.nodes.count * 2
        )
        let branchingCheckpoint = try XCTUnwrap(
            stateRepository.checkpoint(for: "integration:daily:q003")
        )
        XCTAssertTrue(branchingCheckpoint.isCompleted)
        XCTAssertFalse(branchingCheckpoint.visitedNodeIds.contains("daily_q003_cannot_001"))
        XCTAssertTrue(branchingCheckpoint.visitedNodeIds.contains("daily_q003_can_001"))
        XCTAssertEqual(branchingCheckpoint.choiceHistory.last?.nodeId, "daily_q003_001")
        XCTAssertEqual(branchingCheckpoint.choiceHistory.last?.choiceId, "choice_solo_movie")
        XCTAssertEqual(
            branchingCheckpoint.choiceHistory.last?.choiceOrder,
            branchingChoice.choiceOrder
        )
    }

    func testCloseAndReopenStartsFromBeginningKeepingDurableEventState() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()
        let event = try XCTUnwrap(contentRepository.event(id: RootTabView.firstStoryEventID))
        let scenario = try XCTUnwrap(contentRepository.scenario(id: event.entryScenarioId))
        let playbackKey = "integration:resume:middle_001"
        try stateRepository.markUnlocked(eventId: event.eventId, at: fixedNow)

        let firstPlayer = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await firstPlayer.start()
        let firstNodeID = try XCTUnwrap(firstPlayer.currentNode?.nodeId)
        // 冒頭の背景・立ち絵コマンドも訪問履歴に含まれる。
        let initialVisitedNodeIDs = try XCTUnwrap(
            stateRepository.checkpoint(for: playbackKey)
        ).visitedNodeIds
        await firstPlayer.advance(expectedNodeId: firstNodeID)
        let resumableNodeID = try XCTUnwrap(firstPlayer.currentNode?.nodeId)
        XCTAssertNotEqual(resumableNodeID, firstNodeID)
        await firstPlayer.advance(expectedNodeId: firstNodeID)
        XCTAssertEqual(
            firstPlayer.currentNode?.nodeId,
            resumableNodeID,
            "A stale task for the previously rendered node must not advance again"
        )
        firstPlayer.close()

        let resumedPlayer = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await resumedPlayer.start()

        XCTAssertEqual(resumedPlayer.currentNode?.nodeId, firstNodeID)
        XCTAssertFalse(resumedPlayer.isCompleted)
        let reopenedCheckpoint = try XCTUnwrap(stateRepository.checkpoint(for: playbackKey))
        XCTAssertEqual(reopenedCheckpoint.visitedNodeIds, initialVisitedNodeIDs)
        XCTAssertTrue(reopenedCheckpoint.choiceHistory.isEmpty)

        await resumedPlayer.restart()

        XCTAssertEqual(resumedPlayer.currentNode?.nodeId, firstNodeID)
        let restartedCheckpoint = try XCTUnwrap(stateRepository.checkpoint(for: playbackKey))
        XCTAssertEqual(restartedCheckpoint.visitedNodeIds, initialVisitedNodeIDs)
        XCTAssertFalse(restartedCheckpoint.isCompleted)
        let retainedProgress = try XCTUnwrap(
            stateRepository.eventProgress(for: event.eventId)
        )
        XCTAssertTrue(retainedProgress.isUnlocked)
        XCTAssertNotNil(retainedProgress.firstOpenedAt)
        XCTAssertFalse(retainedProgress.isRead)
    }

    func testSkipCompletesEventAndNextOpenStartsFromBeginning() async throws {
        let scenario = StoryScenario(scenarioId: "skip_reread", scenarioType: .smallEvent, nodes: [
            StoryNode(nodeId: "first", lineOrder: 1, speaker: "rio", messageType: .text,
                      text: "最初のセリフ", screenMode: .chat, uiVariant: .dialogue),
            StoryNode(nodeId: "last", lineOrder: 2, speaker: "rio", messageType: .text,
                      text: "最後のセリフ", screenMode: .chat, uiVariant: .dialogue),
        ])
        let event = makeTestEvent(for: scenario, type: .small)
        let contentRepository = try makeTestContentRepository(scenario: scenario, event: event)
        let stateRepository = try makeStateRepository()
        let playbackKey = "integration:skip:reread"
        try stateRepository.markUnlocked(eventId: event.eventId, at: fixedNow)

        let firstPlayer = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await firstPlayer.start()
        let firstNodeID = try XCTUnwrap(firstPlayer.currentNode?.nodeId)
        let initialVisitedNodeIDs = try XCTUnwrap(
            stateRepository.checkpoint(for: playbackKey)
        ).visitedNodeIds

        let didSkip = await firstPlayer.skip()

        XCTAssertTrue(didSkip)
        XCTAssertTrue(firstPlayer.isCompleted)
        XCTAssertTrue(try XCTUnwrap(stateRepository.checkpoint(for: playbackKey)).isCompleted)
        let completedProgress = try XCTUnwrap(
            stateRepository.eventProgress(for: event.eventId)
        )
        XCTAssertTrue(completedProgress.isRead)
        XCTAssertTrue(completedProgress.isCompleted)
        XCTAssertEqual(completedProgress.completionCount, 1)

        let rereadPlayer = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await rereadPlayer.start()

        XCTAssertFalse(rereadPlayer.isCompleted)
        XCTAssertEqual(rereadPlayer.currentNode?.nodeId, firstNodeID)
        let rereadCheckpoint = try XCTUnwrap(
            stateRepository.checkpoint(for: playbackKey)
        )
        XCTAssertFalse(rereadCheckpoint.isCompleted)
        XCTAssertEqual(rereadCheckpoint.visitedNodeIds, initialVisitedNodeIDs)
        XCTAssertEqual(
            try XCTUnwrap(stateRepository.eventProgress(for: event.eventId)).completionCount,
            1,
            "Starting a reread must not count as another completion"
        )
    }

    func testCompletedPrologueOpenedFromCatalogStartsFromBeginning() async throws {
        let scenario = StoryScenario(
            scenarioId: "prologue_test",
            scenarioType: .prologue,
            nodes: [
                StoryNode(
                    nodeId: "prologue_test_001",
                    lineOrder: 1,
                    speaker: "rio",
                    messageType: .text,
                    text: "ほらほらどうしたの〜？",
                    screenMode: .adv,
                    uiVariant: .dialogue
                ),
            ]
        )
        let event = StoryEvent(
            eventId: "event_prologue_test",
            eventType: .prologue,
            title: "プロローグ",
            entryScenarioId: scenario.scenarioId,
            priority: 0,
            repeatable: false,
            cooldownDays: 0,
            background: "bg_protagonist_living_room",
            advancesToPhase: nil,
            chapterId: "chapter_01",
            episodeOrder: 0,
            storyCategory: .main,
            conditions: [],
            notes: nil
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(
                scenarios: [scenario],
                choiceGroups: [],
                events: [event]
            )
        )
        let stateRepository = try makeStateRepository()
        let playbackKey = "event:\(event.eventId)"
        try stateRepository.markUnlocked(eventId: event.eventId, at: fixedNow)

        let firstPlayer = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await firstPlayer.start()
        await firstPlayer.advance()
        XCTAssertTrue(firstPlayer.isCompleted)

        let rereadPlayer = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await rereadPlayer.start()

        XCTAssertFalse(rereadPlayer.isCompleted)
        XCTAssertEqual(rereadPlayer.currentNode?.nodeId, "prologue_test_001")
        XCTAssertEqual(
            try XCTUnwrap(stateRepository.checkpoint(for: playbackKey)).visitedNodeIds,
            ["prologue_test_001"]
        )
        XCTAssertEqual(
            try XCTUnwrap(stateRepository.eventProgress(for: event.eventId)).completionCount,
            1
        )
    }

    func testDailySelectedRepliesAppearInOrderAndSurviveResumeAndCompletion() async throws {
        let scenario = StoryScenario(
            scenarioId: "daily_reply_history",
            scenarioType: .daily,
            nodes: [
                StoryNode(
                    nodeId: "first_prompt",
                    lineOrder: 1,
                    speaker: "character",
                    messageType: .choice,
                    text: "最初の質問",
                    choiceId: "first_replies"
                ),
                StoryNode(
                    nodeId: "first_yes",
                    lineOrder: 2,
                    speaker: "character",
                    messageType: .text,
                    text: "最初の返事",
                    nextNodeId: "first_merge"
                ),
                StoryNode(
                    nodeId: "first_no",
                    lineOrder: 3,
                    speaker: "character",
                    messageType: .text,
                    text: "別の返事",
                    nextNodeId: "first_merge"
                ),
                StoryNode(
                    nodeId: "first_merge",
                    lineOrder: 4,
                    speaker: "character",
                    messageType: .text,
                    text: "合流"
                ),
                StoryNode(
                    nodeId: "second_prompt",
                    lineOrder: 5,
                    speaker: "character",
                    messageType: .choice,
                    text: "次の質問",
                    choiceId: "second_replies"
                ),
                StoryNode(
                    nodeId: "second_yes",
                    lineOrder: 6,
                    speaker: "character",
                    messageType: .text,
                    text: "二つ目の返事",
                    nextNodeId: "reply_end"
                ),
                StoryNode(
                    nodeId: "second_no",
                    lineOrder: 7,
                    speaker: "character",
                    messageType: .text,
                    text: "二つ目の別返事",
                    nextNodeId: "reply_end"
                ),
                StoryNode(
                    nodeId: "reply_end",
                    lineOrder: 8,
                    speaker: "character",
                    messageType: .text,
                    text: "おしまい"
                ),
            ]
        )
        let firstChoices = [
            StoryChoice(choiceOrder: 1, label: "最初の回答", nextNodeId: "first_yes"),
            StoryChoice(choiceOrder: 2, label: "別の回答", nextNodeId: "first_no"),
        ]
        let secondChoices = [
            StoryChoice(choiceOrder: 1, label: "次の回答", nextNodeId: "second_yes"),
            StoryChoice(choiceOrder: 2, label: "次の別回答", nextNodeId: "second_no"),
        ]
        let contentRepository = try StoryContentRepository(content: StoryContentBundle(
            scenarios: [scenario],
            choiceGroups: [
                StoryChoiceGroup(choiceId: "first_replies", choices: firstChoices),
                StoryChoiceGroup(choiceId: "second_replies", choices: secondChoices),
            ],
            events: []
        ))
        let stateRepository = try makeStateRepository()
        let playbackKey = "integration:daily:reply-history"
        let player = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await player.start()
        try await advanceUntilChoice("first_replies", player: player, safetyLimit: 20)
        XCTAssertFalse(player.visibleChatNodes.contains(where: \.isPlayerSpeaker))

        let firstChoice = try XCTUnwrap(player.availableChoices.last)
        await player.selectChoice(firstChoice)
        let firstReply = try XCTUnwrap(player.visibleChatNodes.first(where: \.isPlayerSpeaker))
        XCTAssertEqual(firstReply.messageType, .text)
        XCTAssertEqual(firstReply.text, firstChoice.label)
        XCTAssertEqual(
            Array(player.visibleChatNodes.suffix(3)).map(\.nodeId),
            ["first_prompt", firstReply.nodeId, try XCTUnwrap(player.currentNode?.nodeId)]
        )
        let beforeResume = player.visibleChatNodes
        player.close()

        let resumed = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await resumed.start()
        XCTAssertEqual(resumed.visibleChatNodes, beforeResume)
        XCTAssertEqual(resumed.visibleChatNodes.filter { $0.nodeId == firstReply.nodeId }.count, 1)
        try await advanceUntilChoice("second_replies", player: resumed, safetyLimit: 20)
        let secondChoice = try XCTUnwrap(resumed.availableChoices.first)
        await resumed.selectChoice(secondChoice)
        XCTAssertEqual(
            resumed.visibleChatNodes.filter(\.isPlayerSpeaker).compactMap(\.text),
            [firstChoice.label, secondChoice.label]
        )
        try await driveStartedPlayerToCompletion(resumed, safetyLimit: 20)
        XCTAssertFalse(resumed.isModalPresented)
        let completedHistory = resumed.visibleChatNodes
        let checkpoint = try XCTUnwrap(stateRepository.checkpoint(for: playbackKey))
        XCTAssertEqual(checkpoint.choiceHistory.map(\.label), [firstChoice.label, secondChoice.label])
        XCTAssertTrue(checkpoint.visitedNodeIds.allSatisfy { nodeId in
            scenario.nodes.contains { $0.nodeId == nodeId }
        }, "Presentation-only replies must not become navigation nodes")

        let reopened = makePlayer(
            scenario: scenario,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await reopened.start()
        XCTAssertTrue(reopened.isCompleted)
        XCTAssertEqual(reopened.visibleChatNodes, completedHistory)
        await reopened.restart()
        XCTAssertFalse(reopened.isCompleted)
        XCTAssertFalse(reopened.visibleChatNodes.contains(where: \.isPlayerSpeaker))
        XCTAssertTrue(try XCTUnwrap(stateRepository.checkpoint(for: playbackKey)).choiceHistory.isEmpty)
    }

    func testDailyTerminalChoiceDisplaysOnlyTheSelectedReply() async throws {
        let scenario = StoryScenario(
            scenarioId: "daily_terminal_choice",
            scenarioType: .daily,
            nodes: [StoryNode(
                nodeId: "choose_reply",
                lineOrder: 1,
                speaker: "user",
                messageType: .choice,
                text: "未送信の返信",
                choiceId: "terminal_replies"
            )]
        )
        let choices = [
            StoryChoice(choiceOrder: 1, label: "がんばるよ"),
            StoryChoice(choiceOrder: 2, label: "明日も来るね"),
        ]
        let contentRepository = try StoryContentRepository(content: StoryContentBundle(
            scenarios: [scenario],
            choiceGroups: [StoryChoiceGroup(choiceId: "terminal_replies", choices: choices)],
            events: []
        ))
        let stateRepository = try makeStateRepository()
        let player = makePlayer(
            scenario: scenario,
            playbackKey: "integration:daily:terminal-reply",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await player.start()
        XCTAssertTrue(player.visibleChatNodes.isEmpty)
        await player.selectChoice(choices[1])
        XCTAssertTrue(player.isCompleted)
        XCTAssertFalse(player.isModalPresented)
        XCTAssertEqual(player.visibleChatNodes.compactMap(\.text), [choices[1].label])
        XCTAssertTrue(player.visibleChatNodes.allSatisfy(\.isPlayerSpeaker))
        await player.start()
        XCTAssertTrue(player.isCompleted)
        XCTAssertEqual(player.visibleChatNodes.compactMap(\.text), [choices[1].label])
    }

    func testMissingChoiceGroupContinuesByLineOrder() async throws {
        let missingScenario = StoryScenario(
            scenarioId: "missing_choice_group",
            scenarioType: .daily,
            nodes: [
                StoryNode(
                    nodeId: "missing_choice",
                    lineOrder: 1,
                    speaker: "user",
                    messageType: .choice,
                    choiceId: "not_in_catalog"
                ),
                StoryNode(
                    nodeId: "missing_fallback",
                    lineOrder: 2,
                    speaker: "character",
                    messageType: .text,
                    text: "fallback"
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(
                scenarios: [missingScenario],
                choiceGroups: [],
                events: []
            )
        )
        let stateRepository = try makeStateRepository()
        let player = makePlayer(
            scenario: missingScenario,
            playbackKey: "integration:\(missingScenario.scenarioId)",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()

        XCTAssertEqual(player.currentNode?.nodeId, "missing_fallback")
        XCTAssertTrue(player.availableChoices.isEmpty)
        XCTAssertNotNil(player.recoverableError)
        await player.advance()
        XCTAssertTrue(player.isCompleted)
    }

    func testPlayerIdentifiesTheLastVisibleNodeAsTerminal() async throws {
        let scenario = StoryScenario(
            scenarioId: "terminal_node",
            scenarioType: .middleEvent,
            nodes: [
                StoryNode(
                    nodeId: "first",
                    lineOrder: 1,
                    speaker: "protagonist",
                    messageType: .text,
                    text: "first"
                ),
                StoryNode(
                    nodeId: "last",
                    lineOrder: 2,
                    speaker: "rio",
                    messageType: .text,
                    text: "last"
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(
                scenarios: [scenario],
                choiceGroups: [],
                events: []
            )
        )
        let stateRepository = try makeStateRepository()
        let player = makePlayer(
            scenario: scenario,
            playbackKey: "integration:terminal_node",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()
        XCTAssertEqual(player.currentNode?.nodeId, "first")
        XCTAssertFalse(player.isCurrentNodeTerminal)

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "last")
        XCTAssertTrue(player.isCurrentNodeTerminal)

        await player.advance()
        XCTAssertTrue(player.isCompleted)
        XCTAssertFalse(player.isCurrentNodeTerminal)
    }

    func testEventLogIncludesPresentedTextWithoutSpoilingPendingChatMessages() async throws {
        let scenario = StoryScenario(
            scenarioId: "event_log",
            scenarioType: .middleEvent,
            nodes: [
                StoryNode(
                    nodeId: "scene",
                    lineOrder: 1,
                    speaker: "system",
                    messageType: .action,
                    text: nil,
                    screenMode: .adv,
                    uiVariant: .sceneTransition,
                    command: "scene_change"
                ),
                StoryNode(
                    nodeId: "intro",
                    lineOrder: 2,
                    speaker: "narrator",
                    messageType: .text,
                    text: "導入",
                    screenMode: .adv,
                    uiVariant: .narration
                ),
                StoryNode(
                    nodeId: "to_chat",
                    lineOrder: 3,
                    speaker: "system",
                    messageType: .action,
                    text: "",
                    screenMode: .chat,
                    uiVariant: .sceneTransition,
                    command: "scene_change"
                ),
                StoryNode(
                    nodeId: "player_message",
                    lineOrder: 4,
                    speaker: "protagonist",
                    messageType: .text,
                    text: "送信前の内容",
                    screenMode: .chat,
                    uiVariant: .dialogue
                ),
                StoryNode(
                    nodeId: "rio_message",
                    lineOrder: 5,
                    speaker: "rio",
                    messageType: .text,
                    text: "莉央の返信",
                    screenMode: .chat,
                    uiVariant: .dialogue
                ),
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(
                scenarios: [scenario],
                choiceGroups: [],
                events: []
            )
        )
        let stateRepository = try makeStateRepository()
        let player = makePlayer(
            scenario: scenario,
            playbackKey: "integration:event_log",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        await player.start()
        XCTAssertEqual(player.currentNode?.nodeId, "intro")
        XCTAssertEqual(player.visibleLogNodes.map(\.nodeId), ["intro"])

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "player_message")
        XCTAssertEqual(player.visibleLogNodes.map(\.nodeId), ["intro"])

        await player.advance()
        XCTAssertEqual(player.currentNode?.nodeId, "rio_message")
        XCTAssertEqual(
            player.visibleLogNodes.map(\.nodeId),
            ["intro", "player_message"]
        )

        player.markCurrentNodePresented(expectedNodeId: "rio_message")
        XCTAssertEqual(
            player.visibleLogNodes.map(\.nodeId),
            ["intro", "player_message", "rio_message"]
        )

        await player.advance()
        XCTAssertTrue(player.isCompleted)
        XCTAssertEqual(
            player.visibleLogNodes.map(\.nodeId),
            ["intro", "player_message", "rio_message"]
        )
    }
}

private extension StoryPlayerIntegrationTests {
    // Feature fixtures are deliberately independent of CMS IDs and episode availability.
    // The bundled-content traversal test separately covers the current published stories.
    func makeTestContentRepository(
        scenario: StoryScenario,
        event: StoryEvent? = nil
    ) throws -> StoryContentRepository {
        try StoryContentRepository(content: StoryContentBundle(
            scenarios: [scenario], choiceGroups: [], events: event.map { [$0] } ?? []
        ))
    }

    func makeTestEvent(for scenario: StoryScenario, type: StoryEventType) -> StoryEvent {
        StoryEvent(
            eventId: "event_\(scenario.scenarioId)", eventType: type, title: "テストイベント",
            entryScenarioId: scenario.scenarioId, priority: 0, repeatable: false, cooldownDays: 0,
            background: nil, advancesToPhase: nil, chapterId: "test_chapter", episodeOrder: 1,
            storyCategory: .main, conditions: [], notes: nil
        )
    }

    func makeGeneratedContentRepository() throws -> StoryContentRepository {
        for bundle in [Bundle.main, Bundle(for: StoryPlayerIntegrationTests.self)] {
            if let repository = try? StoryContentRepository(bundle: bundle) {
                return repository
            }
        }

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MesugakiRoutine")
            .appendingPathComponent("Resources")
            .appendingPathComponent("GeneratedScenarios")
            .appendingPathComponent("story_content.generated.json")
        return try StoryContentRepository(data: Data(contentsOf: sourceURL))
    }

    func makeStateRepository() throws -> StoryStateRepository {
        let schema = Schema([
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        retainedContainers.append(container)
        return StoryStateRepository(context: container.mainContext)
    }

    func makePlayer(
        scenario: StoryScenario,
        event: StoryEvent? = nil,
        playbackKey: String,
        contentRepository: StoryContentRepository,
        stateRepository: StoryStateRepository,
        sleep: @escaping StoryPlayerSleep = { _ in }
    ) -> StoryPlayer {
        let now = fixedNow
        return StoryPlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            sleep: sleep,
            logger: { _ in },
            now: { now }
        )
    }

    @discardableResult
    func driveStartedPlayerToCompletion(
        _ player: StoryPlayer,
        safetyLimit: Int,
        observe: ((StoryPlayer) throws -> Void)? = nil
    ) async throws -> Int {
        var stepCount = 0
        while !player.isCompleted, stepCount < safetyLimit {
            try observe?(player)
            if player.isModalPresented {
                await player.dismissModal()
            } else if let choice = player.availableChoices.first {
                await player.selectChoice(choice)
            } else {
                await player.advance()
            }
            stepCount += 1
        }
        try observe?(player)

        XCTAssertTrue(
            player.isCompleted,
            "Player did not complete in \(safetyLimit) steps; current=\(player.currentNode?.nodeId ?? "nil"), error=\(player.recoverableError ?? "nil")"
        )
        XCTAssertLessThan(stepCount, safetyLimit)
        return stepCount
    }

    func advanceUntilChoice(
        _ choiceId: String,
        player: StoryPlayer,
        safetyLimit: Int
    ) async throws {
        var stepCount = 0
        while player.currentNode?.choiceId != choiceId,
              !player.isCompleted,
              stepCount < safetyLimit {
            if player.isModalPresented {
                await player.dismissModal()
            } else if let choice = player.availableChoices.first {
                await player.selectChoice(choice)
            } else {
                await player.advance()
            }
            stepCount += 1
        }

        XCTAssertEqual(player.currentNode?.choiceId, choiceId)
        XCTAssertLessThan(stepCount, safetyLimit)
    }

    func compressed(_ modes: [StoryScreenMode]) -> [StoryScreenMode] {
        modes.reduce(into: []) { result, mode in
            if result.last != mode { result.append(mode) }
        }
    }

}

@MainActor
private final class StoryPlayerSleepProbe {
    weak var player: StoryPlayer?
    private(set) var sawTypingDuringWait = false

    func record(milliseconds: UInt64) {
        guard milliseconds > 0, player?.isTyping == true else { return }
        sawTypingDuringWait = true
    }
}

@MainActor
private final class StoryPlayerHesitationSleepProbe {
    struct Wait {
        let milliseconds: UInt64
        let nodeID: String?
        let isHesitating: Bool
    }

    weak var player: StoryPlayer?
    private(set) var waits: [Wait] = []

    func record(milliseconds: UInt64) {
        waits.append(
            Wait(
                milliseconds: milliseconds,
                nodeID: player?.currentNode?.nodeId,
                isHesitating: player?.isHesitating ?? false
            )
        )
    }
}

@MainActor
private final class StoryPlayerHesitationSleepGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isReleased = false
    var waits: [UInt64] = []
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
