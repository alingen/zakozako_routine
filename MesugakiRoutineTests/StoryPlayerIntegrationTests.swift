import Foundation
import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class StoryPlayerIntegrationTests: XCTestCase {
    private let fixedNow = Date(timeIntervalSince1970: 1_750_000_000)
    private var retainedContainers: [ModelContainer] = []

    func testDayOneThroughSevenScenariosTraverseAndPersistCompletion() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()
        let events = contentRepository.events
            .filter { event in
                event.storyCategory == .main
                    && event.chapterId == "chapter_01"
                    && event.episodeOrder.map { (1...7).contains($0) } == true
            }
            .sorted { ($0.episodeOrder ?? .max) < ($1.episodeOrder ?? .max) }
        var didPresentAudioMessage = false
        var didRetainAudioMessageAfterAdvance = false

        XCTAssertEqual(events.compactMap(\.episodeOrder), Array(1...7))

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
                guard event.eventId == "event_small_002" else { return }
                if player.currentNode?.nodeId == "small_002_025" {
                    didPresentAudioMessage =
                        player.currentNode?.assetId == "audio_zako_onii_recording"
                        && player.activeAudioAssetID == "audio_zako_onii_recording"
                } else if player.visibleChatNodes.contains(where: {
                    $0.nodeId == "small_002_025"
                }) {
                    didRetainAudioMessageAfterAdvance = true
                }
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

        XCTAssertTrue(didPresentAudioMessage)
        XCTAssertTrue(didRetainAudioMessageAfterAdvance)
    }

    func testRealModeTransitionsCGVisibilityAndCompletionUnlock() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()

        let largeEvent = try XCTUnwrap(contentRepository.event(id: "event_large_001"))
        let largeScenario = try XCTUnwrap(
            contentRepository.scenario(id: largeEvent.entryScenarioId)
        )
        let largePlayer = makePlayer(
            scenario: largeScenario,
            event: largeEvent,
            playbackKey: "integration:modes:large_001",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        var largeModes: [StoryScreenMode] = []
        var quotedLineModes: [StoryScreenMode] = []
        var didShowCG = false
        var didHideCGAfterShowing = false

        await largePlayer.start()
        XCTAssertEqual(largePlayer.currentNode?.nodeId, "large_001_002")
        XCTAssertEqual(largePlayer.currentNode?.uiVariant, .narration)
        XCTAssertEqual(largePlayer.backgroundAssetID, "bg_rio_entrance")
        XCTAssertEqual(
            try stateRepository.checkpoint(for: "integration:modes:large_001")?.visitedNodeIds,
            ["large_001_001", "large_001_002"]
        )
        try await driveStartedPlayerToCompletion(
            largePlayer,
            safetyLimit: largeScenario.nodes.count * 3
        ) { player in
            largeModes.append(player.currentMode)
            if player.currentNode?.lineOrder ?? .max < 235,
               player.currentNode?.storyDisplayText.contains("『") == true {
                quotedLineModes.append(player.currentMode)
            }
            if player.cgAssetID == "cg_day7_under_table" {
                didShowCG = true
                if !player.isCompleted {
                    XCTAssertNil(
                        try stateRepository.memoryUnlock(for: "cg_day7_under_table"),
                        "A traversed CG must stay locked until normal completion"
                    )
                }
            } else if didShowCG {
                didHideCGAfterShowing = true
            }
        }

        XCTAssertEqual(compressed(largeModes), [.adv, .chat])
        XCTAssertFalse(quotedLineModes.isEmpty)
        XCTAssertTrue(quotedLineModes.allSatisfy { $0 == .adv })
        XCTAssertTrue(didShowCG)
        XCTAssertTrue(didHideCGAfterShowing)
        let unlockedCG = try XCTUnwrap(
            stateRepository.memoryUnlock(for: "cg_day7_under_table")
        )
        XCTAssertEqual(unlockedCG.sourceEventId, largeEvent.eventId)
        XCTAssertEqual(unlockedCG.sourceScenarioId, largeScenario.scenarioId)

        let callEvent = try XCTUnwrap(contentRepository.event(id: "event_small_003"))
        let callScenario = try XCTUnwrap(
            contentRepository.scenario(id: callEvent.entryScenarioId)
        )
        let sleepProbe = StoryPlayerSleepProbe()
        let callPlayer = makePlayer(
            scenario: callScenario,
            event: callEvent,
            playbackKey: "integration:modes:small_003",
            contentRepository: contentRepository,
            stateRepository: stateRepository,
            sleep: { milliseconds in
                sleepProbe.record(milliseconds: milliseconds)
            }
        )
        sleepProbe.player = callPlayer
        var callModes: [StoryScreenMode] = []
        var observedCallNodeIDs: [String] = []
        var didPresentImageMessage = false
        var didPresentModal = false

        await callPlayer.start()
        try await driveStartedPlayerToCompletion(
            callPlayer,
            safetyLimit: callScenario.nodes.count * 3
        ) { player in
            callModes.append(player.currentMode)
            if let nodeID = player.currentNode?.nodeId {
                observedCallNodeIDs.append(nodeID)
            }
            if player.currentNode?.nodeId == "small_003_010" {
                didPresentImageMessage =
                    player.currentNode?.uiVariant == .imageMessage
                    && player.currentNode?.assetId == "img_day4_handbook"
            }
            if player.currentNode?.nodeId == "small_003_134" {
                didPresentModal = player.isModalPresented
            }
        }

        XCTAssertTrue(containsSubsequence([.chat, .call, .chat], in: compressed(callModes)))
        XCTAssertTrue(observedCallNodeIDs.contains("small_003_070"))
        XCTAssertTrue(observedCallNodeIDs.contains("small_003_071"))
        XCTAssertTrue(didPresentImageMessage)
        XCTAssertTrue(didPresentModal)
        XCTAssertTrue(sleepProbe.sawTypingDuringWait)
    }

    func testMiddleEventSkipsMemoTitleAndEmptySystemTransitions() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()
        let event = try XCTUnwrap(contentRepository.event(id: "event_middle_002"))
        let scenario = try XCTUnwrap(contentRepository.scenario(id: event.entryScenarioId))
        let playbackKey = "integration:hidden-system:middle_002"
        let player = makePlayer(
            scenario: scenario,
            event: event,
            playbackKey: playbackKey,
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )

        XCTAssertFalse(scenario.nodes.contains(where: { $0.uiVariant == .titleCard }))

        await player.start()

        XCTAssertEqual(player.currentNode?.nodeId, "middle_002_004")
        XCTAssertEqual(player.currentNode?.uiVariant, .narration)
        XCTAssertEqual(player.backgroundAssetID, "bg_station_street_evening")
        XCTAssertEqual(
            try stateRepository.checkpoint(for: playbackKey)?.visitedNodeIds,
            ["middle_002_001", "middle_002_003", "middle_002_004"]
        )
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

    func testCloseResumeAndRestartKeepDurableEventState() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()
        let event = try XCTUnwrap(contentRepository.event(id: "event_middle_001"))
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

        XCTAssertEqual(resumedPlayer.currentNode?.nodeId, resumableNodeID)
        XCTAssertFalse(resumedPlayer.isCompleted)

        await resumedPlayer.restart()

        XCTAssertEqual(resumedPlayer.currentNode?.nodeId, firstNodeID)
        let restartedCheckpoint = try XCTUnwrap(stateRepository.checkpoint(for: playbackKey))
        XCTAssertEqual(restartedCheckpoint.visitedNodeIds, [firstNodeID])
        XCTAssertFalse(restartedCheckpoint.isCompleted)
        let retainedProgress = try XCTUnwrap(
            stateRepository.eventProgress(for: event.eventId)
        )
        XCTAssertTrue(retainedProgress.isUnlocked)
        XCTAssertNotNil(retainedProgress.firstOpenedAt)
        XCTAssertFalse(retainedProgress.isRead)
    }

    func testSkipCompletesEventAndNextOpenStartsFromBeginning() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()
        let event = try XCTUnwrap(contentRepository.event(id: "event_small_001"))
        let scenario = try XCTUnwrap(contentRepository.scenario(id: event.entryScenarioId))
        let playbackKey = "integration:skip:small_001"
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
        XCTAssertEqual(rereadCheckpoint.visitedNodeIds, [firstNodeID])
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

    func containsSubsequence<T: Equatable>(_ needle: [T], in haystack: [T]) -> Bool {
        guard !needle.isEmpty else { return true }
        var index = 0
        for element in haystack where element == needle[index] {
            index += 1
            if index == needle.count { return true }
        }
        return false
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
