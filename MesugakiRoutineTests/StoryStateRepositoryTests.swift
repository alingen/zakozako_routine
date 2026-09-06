import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class StoryStateRepositoryTests: XCTestCase {
    private var container: ModelContainer?

    func testCheckpointCanBeResumedWithTraversalStateIntact() throws {
        let repository = try makeRepository()
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let choice = StoryChoiceHistoryEntry(
            nodeId: "choice_node",
            choiceId: "response",
            choiceOrder: 2,
            label: "option",
            nextNodeId: "branch_b"
        )
        let checkpoint = StoryPlaybackCheckpoint(
            playbackKey: "event:test",
            scenarioId: "scenario_test",
            currentNodeId: "branch_b",
            visitedNodeIds: ["start", "choice_node"],
            choiceHistory: [choice],
            seenCGAssetIds: ["cg_test"],
            updatedAt: savedAt
        )

        try repository.saveCheckpoint(checkpoint)

        XCTAssertEqual(try repository.checkpoint(for: "event:test"), checkpoint)
    }

    func testChoiceAndProfileValueAreSavedTogetherWithoutDuplicateHistory() throws {
        let repository = try makeRepository()
        let choice = StoryChoiceHistoryEntry(
            nodeId: "choice_node",
            choiceId: "response",
            choiceOrder: 1,
            label: "accept",
            nextNodeId: "accepted"
        )
        let next = StoryPlaybackCheckpoint(
            playbackKey: "event:choice",
            scenarioId: "scenario_choice",
            currentNodeId: "accepted",
            visitedNodeIds: ["choice_node"],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let firstSave = try repository.saveChoice(
            choice,
            profileKey: "answer",
            profileValue: "accepted",
            next: next
        )
        let secondSave = try repository.saveChoice(
            choice,
            profileKey: "answer",
            profileValue: "accepted",
            next: firstSave
        )

        XCTAssertEqual(secondSave.choiceHistory, [choice])
        XCTAssertEqual(
            try repository.checkpoint(for: "event:choice")?.choiceHistory,
            [choice]
        )
        XCTAssertEqual(try repository.profileValue(for: "answer"), "accepted")
    }

    func testCompletionMarksEventReadAndUnlocksEverySeenCG() throws {
        let repository = try makeRepository()
        let event = try decodeEvent()
        let unlockedAt = Date(timeIntervalSince1970: 1_700_000_200)
        let completedAt = Date(timeIntervalSince1970: 1_700_000_300)
        try repository.markUnlocked(eventId: event.eventId, at: unlockedAt)
        let checkpoint = StoryPlaybackCheckpoint(
            playbackKey: "event:\(event.eventId)",
            scenarioId: event.entryScenarioId,
            currentNodeId: "ending",
            visitedNodeIds: ["start", "ending"],
            seenCGAssetIds: ["cg_a", "cg_b", "cg_a"],
            updatedAt: unlockedAt
        )

        let completed = try repository.complete(
            event: event,
            checkpoint: checkpoint,
            at: completedAt
        )

        XCTAssertTrue(completed.isCompleted)
        XCTAssertNil(completed.currentNodeId)
        let progress = try XCTUnwrap(repository.eventProgress(for: event.eventId))
        XCTAssertTrue(progress.isUnlocked)
        XCTAssertTrue(progress.isRead)
        XCTAssertTrue(progress.isCompleted)
        XCTAssertEqual(progress.completionCount, 1)
        XCTAssertEqual(progress.readAt, completedAt)
        XCTAssertEqual(Set(try repository.memoryUnlocks().map(\.assetId)), ["cg_a", "cg_b"])
        XCTAssertEqual(try repository.memoryUnlock(for: "cg_a")?.sourceEventId, event.eventId)
    }

    func testRestartClearsPlaybackButKeepsReadAndMemoryState() throws {
        let repository = try makeRepository()
        let event = try decodeEvent()
        let completedAt = Date(timeIntervalSince1970: 1_700_000_400)
        let playbackKey = "event:\(event.eventId)"
        let checkpoint = StoryPlaybackCheckpoint(
            playbackKey: playbackKey,
            scenarioId: event.entryScenarioId,
            currentNodeId: "ending",
            visitedNodeIds: ["start", "ending"],
            choiceHistory: [
                StoryChoiceHistoryEntry(
                    nodeId: "choice_node",
                    choiceId: "response",
                    choiceOrder: 1,
                    label: "accept",
                    nextNodeId: "ending"
                )
            ],
            seenCGAssetIds: ["cg_kept"],
            updatedAt: completedAt
        )
        _ = try repository.complete(event: event, checkpoint: checkpoint, at: completedAt)

        let restarted = try repository.restartPlayback(
            playbackKey: playbackKey,
            scenarioId: event.entryScenarioId,
            at: completedAt.addingTimeInterval(60)
        )

        XCTAssertFalse(restarted.isCompleted)
        XCTAssertNil(restarted.currentNodeId)
        XCTAssertTrue(restarted.visitedNodeIds.isEmpty)
        XCTAssertTrue(restarted.choiceHistory.isEmpty)
        XCTAssertTrue(restarted.seenCGAssetIds.isEmpty)
        XCTAssertTrue(try XCTUnwrap(repository.eventProgress(for: event.eventId)).isRead)
        XCTAssertNotNil(try repository.memoryUnlock(for: "cg_kept"))
    }

    private func makeRepository() throws -> StoryStateRepository {
        let schema = Schema([
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        return StoryStateRepository(context: container.mainContext)
    }

    private func decodeEvent() throws -> StoryEvent {
        let json =
            """
            {
              "eventId": "event_state_test",
              "eventType": "small_event",
              "title": "state fixture",
              "entryScenarioId": "scenario_state_test",
              "priority": 1,
              "repeatable": true,
              "cooldownDays": 0,
              "conditions": []
            }
            """
        return try JSONDecoder().decode(StoryEvent.self, from: Data(json.utf8))
    }
}
