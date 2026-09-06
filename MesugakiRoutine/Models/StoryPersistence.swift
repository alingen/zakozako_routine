import Foundation
import SwiftData

/// One choice made while traversing a scenario. The sheet does not give each
/// option its own id, so `(nodeId, choiceId, choiceOrder)` is the stable key.
struct StoryChoiceHistoryEntry: Codable, Hashable, Identifiable {
    let nodeId: String
    let choiceId: String
    let choiceOrder: Int
    let label: String
    let nextNodeId: String?

    var id: String { "\(nodeId)|\(choiceId)|\(choiceOrder)" }
}

/// Value object passed between the player and persistence repository.
/// `currentNodeId` is the node that should be shown again on resume.
struct StoryPlaybackCheckpoint: Codable, Hashable {
    let playbackKey: String
    let scenarioId: String
    var currentNodeId: String?
    var visitedNodeIds: [String]
    var choiceHistory: [StoryChoiceHistoryEntry]
    var seenCGAssetIds: [String]
    var isCompleted: Bool
    var updatedAt: Date

    init(
        playbackKey: String,
        scenarioId: String,
        currentNodeId: String? = nil,
        visitedNodeIds: [String] = [],
        choiceHistory: [StoryChoiceHistoryEntry] = [],
        seenCGAssetIds: [String] = [],
        isCompleted: Bool = false,
        updatedAt: Date = .now
    ) {
        self.playbackKey = playbackKey
        self.scenarioId = scenarioId
        self.currentNodeId = currentNodeId
        self.visitedNodeIds = visitedNodeIds
        self.choiceHistory = choiceHistory
        self.seenCGAssetIds = seenCGAssetIds
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }
}

/// Persistent unlock/read state for an event definition from the CMS.
@Model
final class StoryEventProgress {
    @Attribute(.unique) var eventId: String
    var unlockedAt: Date?
    var firstOpenedAt: Date?
    var readAt: Date?
    var completedAt: Date?
    var completionCount: Int
    var updatedAt: Date

    init(
        eventId: String,
        unlockedAt: Date? = nil,
        firstOpenedAt: Date? = nil,
        readAt: Date? = nil,
        completedAt: Date? = nil,
        completionCount: Int = 0,
        updatedAt: Date = .now
    ) {
        self.eventId = eventId
        self.unlockedAt = unlockedAt
        self.firstOpenedAt = firstOpenedAt
        self.readAt = readAt
        self.completedAt = completedAt
        self.completionCount = completionCount
        self.updatedAt = updatedAt
    }

    var isUnlocked: Bool { unlockedAt != nil }
    var isNew: Bool { isUnlocked && firstOpenedAt == nil }
    var isRead: Bool { readAt != nil }
    var isCompleted: Bool { completedAt != nil }
}

/// Resume checkpoint for either an event or a daily scenario.
///
/// Node ids and CG ids are directly storable SwiftData arrays. Choice history
/// is encoded as JSON `Data`, because it is a structured value and should not
/// become a separate mutable relationship graph.
@Model
final class StoryPlaybackProgress {
    @Attribute(.unique) var playbackKey: String
    var scenarioId: String
    var currentNodeId: String?
    var visitedNodeIds: [String]
    var choiceHistoryData: Data
    var seenCGAssetIds: [String]
    var isCompleted: Bool
    var updatedAt: Date

    init(
        playbackKey: String,
        scenarioId: String,
        currentNodeId: String? = nil,
        visitedNodeIds: [String] = [],
        choiceHistoryData: Data = Data(),
        seenCGAssetIds: [String] = [],
        isCompleted: Bool = false,
        updatedAt: Date = .now
    ) {
        self.playbackKey = playbackKey
        self.scenarioId = scenarioId
        self.currentNodeId = currentNodeId
        self.visitedNodeIds = visitedNodeIds
        self.choiceHistoryData = choiceHistoryData
        self.seenCGAssetIds = seenCGAssetIds
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }

    func choiceHistory() throws -> [StoryChoiceHistoryEntry] {
        guard !choiceHistoryData.isEmpty else { return [] }
        return try JSONDecoder().decode([StoryChoiceHistoryEntry].self, from: choiceHistoryData)
    }

    func setChoiceHistory(_ history: [StoryChoiceHistoryEntry]) throws {
        choiceHistoryData = history.isEmpty ? Data() : try JSONEncoder().encode(history)
    }

    func checkpoint() throws -> StoryPlaybackCheckpoint {
        StoryPlaybackCheckpoint(
            playbackKey: playbackKey,
            scenarioId: scenarioId,
            currentNodeId: currentNodeId,
            visitedNodeIds: visitedNodeIds,
            choiceHistory: try choiceHistory(),
            seenCGAssetIds: seenCGAssetIds,
            isCompleted: isCompleted,
            updatedAt: updatedAt
        )
    }

    func apply(_ checkpoint: StoryPlaybackCheckpoint) throws {
        scenarioId = checkpoint.scenarioId
        currentNodeId = checkpoint.currentNodeId
        visitedNodeIds = checkpoint.visitedNodeIds
        try setChoiceHistory(checkpoint.choiceHistory)
        seenCGAssetIds = checkpoint.seenCGAssetIds
        isCompleted = checkpoint.isCompleted
        updatedAt = checkpoint.updatedAt
    }
}

/// Dynamic profile/story value written by `save_key` / `save_value`.
@Model
final class StoryProfileValue {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Date

    init(key: String, value: String, updatedAt: Date = .now) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}

/// A CG made available in the memories gallery after normal story completion.
@Model
final class StoryMemoryUnlock {
    @Attribute(.unique) var assetId: String
    var sourceEventId: String?
    var sourceScenarioId: String
    var unlockedAt: Date

    init(
        assetId: String,
        sourceEventId: String? = nil,
        sourceScenarioId: String,
        unlockedAt: Date = .now
    ) {
        self.assetId = assetId
        self.sourceEventId = sourceEventId
        self.sourceScenarioId = sourceScenarioId
        self.unlockedAt = unlockedAt
    }
}
