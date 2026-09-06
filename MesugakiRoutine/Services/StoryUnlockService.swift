import Foundation

struct StoryEventUnlockEvaluation: Identifiable, Equatable {
    let event: StoryEvent
    let evaluation: StoryEventEvaluation
    let isUnlocked: Bool
    let wasNewlyUnlocked: Bool

    var id: String { event.eventId }
    var conditions: [StoryConditionEvaluation] { evaluation.conditions }
    var canPlay: Bool { isUnlocked && evaluation.accessDecision.isAllowed }
}

struct StoryUnlockRefreshResult: Equatable {
    let events: [StoryEventUnlockEvaluation]
    let newlyUnlockedEventIds: Set<String>
}

/// Evaluates current CMS conditions and persists only transitions to unlocked.
/// Unlock is monotonic: a later false condition never deletes `unlockedAt`.
@MainActor
final class StoryUnlockService {
    private let contentRepository: StoryContentRepository
    private let stateRepository: StoryStateRepository
    private let metricsProvider: any StoryProgressMetricsProviding
    private let evaluator: StoryConditionEvaluator

    init(
        contentRepository: StoryContentRepository,
        stateRepository: StoryStateRepository,
        metricsProvider: any StoryProgressMetricsProviding,
        evaluator: StoryConditionEvaluator = StoryConditionEvaluator()
    ) {
        self.contentRepository = contentRepository
        self.stateRepository = stateRepository
        self.metricsProvider = metricsProvider
        self.evaluator = evaluator
    }

    /// Read-only evaluation for list/progress UI.
    func evaluations(
        at date: Date = .now,
        calendar: Calendar = .current
    ) throws -> [StoryEventUnlockEvaluation] {
        let metrics = try metricsProvider.current(at: date, calendar: calendar)
        let unlocked = Set(
            try stateRepository.eventProgresses()
                .filter(\.isUnlocked)
                .map(\.eventId)
        )
        return contentRepository.events.map { event in
            StoryEventUnlockEvaluation(
                event: event,
                evaluation: evaluator.evaluate(event: event, metrics: metrics),
                isUnlocked: unlocked.contains(event.eventId),
                wasNewlyUnlocked: false
            )
        }
    }

    /// Evaluates all event condition rows as AND and commits newly satisfied
    /// event ids in one repository save.
    @discardableResult
    func refreshUnlocks(
        at date: Date = .now,
        calendar: Calendar = .current
    ) throws -> StoryUnlockRefreshResult {
        let metrics = try metricsProvider.current(at: date, calendar: calendar)
        let previouslyUnlocked = Set(
            try stateRepository.eventProgresses()
                .filter(\.isUnlocked)
                .map(\.eventId)
        )

        let rawEvaluations = contentRepository.events.map { event in
            (event, evaluator.evaluate(event: event, metrics: metrics))
        }
        let requestedUnlocks = rawEvaluations.compactMap { event, evaluation in
            // CMS progression is durable independently from a temporary
            // product entitlement. Access policy controls playback only.
            !previouslyUnlocked.contains(event.eventId) && evaluation.conditionsSatisfied
                ? event.eventId
                : nil
        }
        let newlyUnlocked = try stateRepository.markUnlocked(
            eventIds: requestedUnlocks,
            at: date
        )

        let rows = rawEvaluations.map { event, evaluation in
            StoryEventUnlockEvaluation(
                event: event,
                evaluation: evaluation,
                isUnlocked: previouslyUnlocked.contains(event.eventId)
                    || newlyUnlocked.contains(event.eventId),
                wasNewlyUnlocked: newlyUnlocked.contains(event.eventId)
            )
        }
        return StoryUnlockRefreshResult(
            events: rows,
            newlyUnlockedEventIds: newlyUnlocked
        )
    }
}
