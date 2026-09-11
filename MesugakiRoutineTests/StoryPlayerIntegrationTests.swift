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

    func testRealDailyDanglingChoiceRecoversAndAnotherChoicePersistsValue() async throws {
        let contentRepository = try makeGeneratedContentRepository()
        let stateRepository = try makeStateRepository()

        let danglingScenario = try XCTUnwrap(contentRepository.scenario(id: "daily_001"))
        let danglingPlayer = makePlayer(
            scenario: danglingScenario,
            playbackKey: "integration:daily:001",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await danglingPlayer.start()
        try await advanceUntilChoice(
            "first_day_can_do",
            player: danglingPlayer,
            safetyLimit: danglingScenario.nodes.count * 2
        )
        let danglingChoice = try XCTUnwrap(danglingPlayer.availableChoices.first)
        XCTAssertEqual(danglingChoice.nextNodeId, "daily_001_10")

        await danglingPlayer.selectChoice(danglingChoice)

        XCTAssertEqual(danglingPlayer.currentNode?.nodeId, "daily_001_06")
        XCTAssertTrue(danglingPlayer.recoverableError?.contains("daily_001_10") == true)
        try await driveStartedPlayerToCompletion(
            danglingPlayer,
            safetyLimit: danglingScenario.nodes.count * 2
        )
        let danglingCheckpoint = try XCTUnwrap(
            stateRepository.checkpoint(for: "integration:daily:001")
        )
        XCTAssertTrue(danglingCheckpoint.isCompleted)
        XCTAssertTrue(danglingCheckpoint.visitedNodeIds.contains("daily_001_06"))
        XCTAssertFalse(danglingCheckpoint.visitedNodeIds.contains("daily_001_07"))

        let savingScenario = try XCTUnwrap(contentRepository.scenario(id: "daily_002"))
        let savingPlayer = makePlayer(
            scenario: savingScenario,
            playbackKey: "integration:daily:002",
            contentRepository: contentRepository,
            stateRepository: stateRepository
        )
        await savingPlayer.start()
        try await advanceUntilChoice(
            "choice_siblings",
            player: savingPlayer,
            safetyLimit: savingScenario.nodes.count * 2
        )
        let savingChoice = try XCTUnwrap(savingPlayer.availableChoices.first)

        await savingPlayer.selectChoice(savingChoice)

        XCTAssertEqual(savingChoice.saveKey, "hasSiblings")
        XCTAssertEqual(try stateRepository.profileValue(for: "hasSiblings"), savingChoice.saveValue)
        let choiceCheckpoint = try XCTUnwrap(
            stateRepository.checkpoint(for: "integration:daily:002")
        )
        XCTAssertEqual(choiceCheckpoint.choiceHistory.last?.nodeId, "daily_002_03")
        XCTAssertEqual(choiceCheckpoint.choiceHistory.last?.choiceId, "choice_siblings")
        XCTAssertEqual(choiceCheckpoint.choiceHistory.last?.choiceOrder, savingChoice.choiceOrder)

        try await driveStartedPlayerToCompletion(
            savingPlayer,
            safetyLimit: savingScenario.nodes.count * 2
        )
        XCTAssertTrue(
            try XCTUnwrap(stateRepository.checkpoint(for: "integration:daily:002")).isCompleted
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

    func testMissingAndFullyFilteredChoiceGroupsContinueByLineOrder() async throws {
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
        let filteredScenario = StoryScenario(
            scenarioId: "filtered_choice_group",
            scenarioType: .daily,
            nodes: [
                StoryNode(
                    nodeId: "filtered_choice",
                    lineOrder: 1,
                    speaker: "user",
                    messageType: .choice,
                    choiceId: "guarded"
                ),
                StoryNode(
                    nodeId: "filtered_fallback",
                    lineOrder: 2,
                    speaker: "character",
                    messageType: .text,
                    text: "fallback"
                ),
            ]
        )
        let guardedGroup = StoryChoiceGroup(
            choiceId: "guarded",
            choices: [
                StoryChoice(
                    choiceOrder: 1,
                    label: "locked",
                    requiredKey: "missing_profile_flag",
                    requiredOperator: .equal,
                    requiredValue: "yes"
                )
            ]
        )
        let contentRepository = try StoryContentRepository(
            content: StoryContentBundle(
                scenarios: [missingScenario, filteredScenario],
                choiceGroups: [guardedGroup],
                events: []
            )
        )
        let stateRepository = try makeStateRepository()

        for (scenario, expectedNodeID) in [
            (missingScenario, "missing_fallback"),
            (filteredScenario, "filtered_fallback"),
        ] {
            let player = makePlayer(
                scenario: scenario,
                playbackKey: "integration:\(scenario.scenarioId)",
                contentRepository: contentRepository,
                stateRepository: stateRepository
            )

            await player.start()

            XCTAssertEqual(player.currentNode?.nodeId, expectedNodeID)
            XCTAssertTrue(player.availableChoices.isEmpty)
            XCTAssertNotNil(player.recoverableError)
            await player.advance()
            XCTAssertTrue(player.isCompleted)
        }
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
