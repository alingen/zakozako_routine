import Foundation
import SwiftData

enum StoryStateRepositoryError: LocalizedError, Equatable {
    case mismatchedPlaybackKey(expected: String, actual: String)
    case mismatchedScenario(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .mismatchedPlaybackKey(let expected, let actual):
            return "Playback key mismatch. Expected \(expected), got \(actual)."
        case .mismatchedScenario(let expected, let actual):
            return "Scenario mismatch. Expected \(expected), got \(actual)."
        }
    }
}

/// Owns all mutable story state in one `ModelContext`.
///
/// Compound operations intentionally mutate every model first and call
/// `context.save()` once, so a selected choice cannot be persisted without its
/// profile value/checkpoint and completion cannot be persisted without its CGs.
@MainActor
final class StoryStateRepository {
    static let relationshipPhaseKey = "relationship_phase"

    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Event progress

    func eventProgresses() throws -> [StoryEventProgress] {
        try context.fetch(FetchDescriptor<StoryEventProgress>())
            .sorted { $0.eventId.localizedStandardCompare($1.eventId) == .orderedAscending }
    }

    func eventProgress(for eventId: String) throws -> StoryEventProgress? {
        try context.fetch(FetchDescriptor<StoryEventProgress>())
            .first { $0.eventId == eventId }
    }

    /// Returns true only when this call transitioned the event to unlocked.
    @discardableResult
    func markUnlocked(eventId: String, at date: Date = .now) throws -> Bool {
        let progress = try fetchOrCreateEventProgress(eventId: eventId, at: date)
        guard progress.unlockedAt == nil else { return false }
        progress.unlockedAt = date
        progress.updatedAt = date
        try context.save()
        return true
    }

    /// Batch form used by the unlock service. Previously unlocked events are
    /// left untouched and therefore never become locked again.
    @discardableResult
    func markUnlocked(eventIds: [String], at date: Date = .now) throws -> Set<String> {
        var changed = Set<String>()
        for eventId in eventIds {
            let progress = try fetchOrCreateEventProgress(eventId: eventId, at: date)
            guard progress.unlockedAt == nil else { continue }
            progress.unlockedAt = date
            progress.updatedAt = date
            changed.insert(eventId)
        }
        if !changed.isEmpty { try context.save() }
        return changed
    }

    func markOpened(eventId: String, at date: Date = .now) throws {
        let progress = try fetchOrCreateEventProgress(eventId: eventId, at: date)
        guard progress.firstOpenedAt == nil else { return }
        progress.firstOpenedAt = date
        progress.updatedAt = date
        try context.save()
    }

    // MARK: - Playback checkpoints

    func checkpoint(for playbackKey: String) throws -> StoryPlaybackCheckpoint? {
        try playbackProgress(for: playbackKey)?.checkpoint()
    }

    func saveCheckpoint(_ checkpoint: StoryPlaybackCheckpoint) throws {
        let progress = try fetchOrCreatePlaybackProgress(
            playbackKey: checkpoint.playbackKey,
            scenarioId: checkpoint.scenarioId,
            at: checkpoint.updatedAt
        )
        try validate(progress: progress, checkpoint: checkpoint)
        try progress.apply(checkpoint)
        try context.save()
    }

    /// Saves an optional node-level profile mutation and its checkpoint in one
    /// transaction. Blank keys are treated as absent CMS values.
    func saveCheckpoint(
        _ checkpoint: StoryPlaybackCheckpoint,
        profileKey: String?,
        profileValue: String?
    ) throws {
        let progress = try fetchOrCreatePlaybackProgress(
            playbackKey: checkpoint.playbackKey,
            scenarioId: checkpoint.scenarioId,
            at: checkpoint.updatedAt
        )
        try validate(progress: progress, checkpoint: checkpoint)
        try progress.apply(checkpoint)
        try upsertProfileValueIfPresent(
            key: profileKey,
            value: profileValue,
            at: checkpoint.updatedAt
        )
        try context.save()
    }

    /// Records the selected option, its optional `save_key/save_value`, and the
    /// checkpoint already pointing at the selected branch, with one save.
    @discardableResult
    func saveChoice(
        _ selection: StoryChoiceHistoryEntry,
        profileKey: String?,
        profileValue: String?,
        next checkpoint: StoryPlaybackCheckpoint
    ) throws -> StoryPlaybackCheckpoint {
        var updated = checkpoint
        if !updated.choiceHistory.contains(where: { $0.id == selection.id }) {
            updated.choiceHistory.append(selection)
        }

        let progress = try fetchOrCreatePlaybackProgress(
            playbackKey: updated.playbackKey,
            scenarioId: updated.scenarioId,
            at: updated.updatedAt
        )
        try validate(progress: progress, checkpoint: updated)
        try progress.apply(updated)
        try upsertProfileValueIfPresent(
            key: profileKey,
            value: profileValue,
            at: updated.updatedAt
        )
        try context.save()
        return updated
    }

    /// Clears only the playback progress. Event unlock/read state and memory
    /// unlocks are deliberately retained for rereading.
    @discardableResult
    func restartPlayback(
        playbackKey: String,
        scenarioId: String,
        at date: Date = .now
    ) throws -> StoryPlaybackCheckpoint {
        let fresh = StoryPlaybackCheckpoint(
            playbackKey: playbackKey,
            scenarioId: scenarioId,
            updatedAt: date
        )
        let progress = try fetchOrCreatePlaybackProgress(
            playbackKey: playbackKey,
            scenarioId: scenarioId,
            at: date
        )
        // A CMS update may intentionally repoint the same event at a new entry
        // scenario. Restart is the explicit safe point where that replacement
        // is allowed.
        try progress.apply(fresh)
        try context.save()
        return fresh
    }

    // MARK: - Completion and memories

    /// Commits completion, read state, completion count, visited CG unlocks and
    /// `advances_to_phase` as a single SwiftData transaction.
    @discardableResult
    func complete(
        event: StoryEvent?,
        checkpoint: StoryPlaybackCheckpoint,
        at date: Date = .now
    ) throws -> StoryPlaybackCheckpoint {
        var completed = checkpoint
        completed.currentNodeId = nil
        completed.isCompleted = true
        completed.updatedAt = date

        let playback = try fetchOrCreatePlaybackProgress(
            playbackKey: completed.playbackKey,
            scenarioId: completed.scenarioId,
            at: date
        )
        try validate(progress: playback, checkpoint: completed)
        try playback.apply(completed)

        if let event {
            let progress = try fetchOrCreateEventProgress(eventId: event.eventId, at: date)
            if progress.firstOpenedAt == nil { progress.firstOpenedAt = date }
            if progress.readAt == nil { progress.readAt = date }
            progress.completedAt = date
            progress.completionCount += 1
            progress.updatedAt = date
        }

        for assetId in Set(completed.seenCGAssetIds) where !assetId.isEmpty {
            if let memory = try memoryUnlock(for: assetId) {
                if memory.sourceEventId == nil { memory.sourceEventId = event?.eventId }
            } else {
                context.insert(
                    StoryMemoryUnlock(
                        assetId: assetId,
                        sourceEventId: event?.eventId,
                        sourceScenarioId: completed.scenarioId,
                        unlockedAt: date
                    )
                )
            }
        }

        if let targetPhase = event?.advancesToPhase {
            let current = try profileValue(for: Self.relationshipPhaseKey)
                .flatMap(Int.init) ?? 0
            if targetPhase > current {
                try upsertProfileValueIfPresent(
                    key: Self.relationshipPhaseKey,
                    value: String(targetPhase),
                    at: date
                )
            }
        }

        try context.save()
        return completed
    }

    // MARK: - Profile values

    func profileValues() throws -> [String: String] {
        Dictionary(
            uniqueKeysWithValues: try context.fetch(FetchDescriptor<StoryProfileValue>())
                .map { ($0.key, $0.value) }
        )
    }

    func profileValue(for key: String) throws -> String? {
        try profileValueModel(for: key)?.value
    }

    func relationshipPhase() throws -> Int {
        try profileValue(for: Self.relationshipPhaseKey).flatMap(Int.init) ?? 0
    }

    // MARK: - Memory unlocks

    func memoryUnlocks() throws -> [StoryMemoryUnlock] {
        try context.fetch(FetchDescriptor<StoryMemoryUnlock>())
            .sorted { $0.unlockedAt < $1.unlockedAt }
    }

    func memoryUnlock(for assetId: String) throws -> StoryMemoryUnlock? {
        try context.fetch(FetchDescriptor<StoryMemoryUnlock>())
            .first { $0.assetId == assetId }
    }

    // MARK: - Internal mutation helpers (never save)

    private func fetchOrCreateEventProgress(
        eventId: String,
        at date: Date
    ) throws -> StoryEventProgress {
        if let existing = try eventProgress(for: eventId) { return existing }
        let created = StoryEventProgress(eventId: eventId, updatedAt: date)
        context.insert(created)
        return created
    }

    private func playbackProgress(for playbackKey: String) throws -> StoryPlaybackProgress? {
        try context.fetch(FetchDescriptor<StoryPlaybackProgress>())
            .first { $0.playbackKey == playbackKey }
    }

    private func fetchOrCreatePlaybackProgress(
        playbackKey: String,
        scenarioId: String,
        at date: Date
    ) throws -> StoryPlaybackProgress {
        if let existing = try playbackProgress(for: playbackKey) { return existing }
        let created = StoryPlaybackProgress(
            playbackKey: playbackKey,
            scenarioId: scenarioId,
            updatedAt: date
        )
        context.insert(created)
        return created
    }

    private func validate(
        progress: StoryPlaybackProgress,
        checkpoint: StoryPlaybackCheckpoint
    ) throws {
        guard progress.playbackKey == checkpoint.playbackKey else {
            throw StoryStateRepositoryError.mismatchedPlaybackKey(
                expected: progress.playbackKey,
                actual: checkpoint.playbackKey
            )
        }
        guard progress.scenarioId == checkpoint.scenarioId else {
            throw StoryStateRepositoryError.mismatchedScenario(
                expected: progress.scenarioId,
                actual: checkpoint.scenarioId
            )
        }
    }

    private func profileValueModel(for key: String) throws -> StoryProfileValue? {
        try context.fetch(FetchDescriptor<StoryProfileValue>())
            .first { $0.key == key }
    }

    private func upsertProfileValueIfPresent(
        key: String?,
        value: String?,
        at date: Date
    ) throws {
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty,
              let value else {
            return
        }
        if let existing = try profileValueModel(for: key) {
            existing.value = value
            existing.updatedAt = date
        } else {
            context.insert(StoryProfileValue(key: key, value: value, updatedAt: date))
        }
    }
}
