import Foundation
import SwiftData

/// 保存済みの事実から、その時点でリアクション条件に使える値を組み立てる。
/// この構造体自体は保存せず、状況別のBooleanも保持しない。
struct ReactionContext {
    let activeRoutineIDs: [UUID]
    let todayRoutineIDs: [UUID]
    let todayCompletedRoutineIDs: [UUID]
    let routinePeriodFacts: [RoutinePeriodFact]

    let currentStreak: Int
    let bestStreak: Int
    let totalCompletionDays: Int
    let lastCompletionAt: Date?
    let allCompletedAt: Date?
    let daysSinceLastCompletion: Int?

    let todayProhibitionOutcome: BlockedBehaviorDayOutcome?
    let todayProhibitionUrgeCount: Int
    let todayProhibitionFailCount: Int
    let lastProhibitionUrgeAt: Date?
    let lastProhibitionFailedAt: Date?

    let lastAppOpenAt: Date?
    let previousAppOpenAt: Date?
    let daysSinceLastAppOpen: Int?
    let daysSincePreviousAppOpen: Int?
    let todayInteractionOpenCount: Int
    let todayCharacterTapCount: Int
    var userActionEvents: [UserActionEvent] = []
    /// 前アプリ日の同じ禁止項目について、既存の日別履歴で「守れた」が確定したurge。
    var resolvedKeptUrgeIDs: [UUID] = []

    var todayRoutineCount: Int { todayRoutineIDs.count }
    var todayCompletedCount: Int { todayCompletedRoutineIDs.count }
    var remainingRoutineCount: Int { todayRoutineCount - todayCompletedCount }
    var isAllCompleted: Bool { todayRoutineCount > 0 && remainingRoutineCount == 0 }
}

@MainActor
struct ReactionContextProvider {
    let routineRepository: RoutineRepository
    let blockedBehaviorRepository: BlockedBehaviorRepository
    let userActionEventRepository: UserActionEventRepository

    init(context: ModelContext) {
        routineRepository = RoutineRepository(context: context)
        blockedBehaviorRepository = BlockedBehaviorRepository(context: context)
        userActionEventRepository = UserActionEventRepository(context: context)
    }

    func current(now: Date = .now, calendar: Calendar = .current) throws -> ReactionContext {
        let routines = routineRepository.fetchAll()
        let todayRoutines = HomeViewModel.computeTodayRoutines(
            routines,
            calendar: calendar,
            now: now
        )
        let completedToday = todayRoutines.filter { $0.isComplete(now: now, calendar: calendar) }
        let completedTodayIDs = Set(completedToday.map(\.id))
        let facts = routines.flatMap {
            RoutineYearStatisticsCalculator.periodFacts(for: $0, now: now, calendar: calendar)
        }
        let completionDates = facts.compactMap(\.completedAt)
        let completionDays = Set(completionDates.map {
            AppDay.startOfDay(for: $0, calendar: calendar)
        })
        let lastCompletionAt = completionDates.max()

        let todayStart = AppDay.startOfDay(for: now, calendar: calendar)
        let events = try userActionEventRepository.fetchAll()
            .filter { $0.occurredAt <= now }
        let todayEvents = events.filter { $0.occurredAt >= todayStart }
        let appOpenDates = events
            .filter { $0.eventType == .appOpened }
            .map(\.occurredAt)
        let lastAppOpenAt = appOpenDates.last
        let previousAppOpenAt = appOpenDates.dropLast().last
        let lastUrgeAt = events.last { $0.eventType == .prohibitionUrge }?.occurredAt
        let lastFailureAt = events.last { $0.eventType == .prohibitionFailed }?.occurredAt

        let activeBehavior = blockedBehaviorRepository.fetchActive()
        let prohibitionOutcome = activeBehavior.flatMap { behavior in
            BlockedBehaviorHistory(behavior: behavior, now: now, calendar: calendar)
                .outcome(onCalendarDay: calendar.startOfDay(for: AppDay.anchor(now, calendar: calendar)))
        }
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart) ?? todayStart
        let behaviors = Dictionary(uniqueKeysWithValues: blockedBehaviorRepository.fetchAll().map { ($0.id, $0) })
        let keptUrges = events.filter { event in
            guard event.eventType == .prohibitionUrge,
                  event.occurredAt >= yesterdayStart, event.occurredAt < todayStart,
                  let targetID = event.targetID, let behavior = behaviors[targetID] else { return false }
            return BlockedBehaviorHistory(behavior: behavior, now: now, calendar: calendar)
                .outcome(onCalendarDay: BlockedBehaviorHistory.calendarDay(of: event.occurredAt, calendar: calendar)) == .kept
        }

        return ReactionContext(
            activeRoutineIDs: routines.filter(\.isActive).map(\.id),
            todayRoutineIDs: todayRoutines.map(\.id),
            todayCompletedRoutineIDs: completedToday.map(\.id),
            routinePeriodFacts: facts,
            currentStreak: RoutineStreak.overallStreak(
                completionDates: completionDates,
                now: now,
                calendar: calendar
            ),
            bestStreak: RoutineStreak.overallBestStreak(
                completionDates: completionDates,
                calendar: calendar
            ),
            totalCompletionDays: completionDays.count,
            lastCompletionAt: lastCompletionAt,
            allCompletedAt: completedToday.count == todayRoutines.count && !todayRoutines.isEmpty
                ? facts.filter { completedTodayIDs.contains($0.routineID) }
                    .compactMap(\.completedAt).max()
                : nil,
            daysSinceLastCompletion: lastCompletionAt.map {
                appDays(from: $0, to: now, calendar: calendar)
            },
            todayProhibitionOutcome: prohibitionOutcome,
            todayProhibitionUrgeCount: todayEvents.filter { $0.eventType == .prohibitionUrge }.count,
            todayProhibitionFailCount: todayEvents.filter { $0.eventType == .prohibitionFailed }.count,
            lastProhibitionUrgeAt: lastUrgeAt,
            lastProhibitionFailedAt: lastFailureAt,
            lastAppOpenAt: lastAppOpenAt,
            previousAppOpenAt: previousAppOpenAt,
            daysSinceLastAppOpen: lastAppOpenAt.map {
                appDays(from: $0, to: now, calendar: calendar)
            },
            daysSincePreviousAppOpen: previousAppOpenAt.map {
                appDays(from: $0, to: lastAppOpenAt ?? now, calendar: calendar)
            },
            todayInteractionOpenCount: todayEvents.filter {
                $0.eventType == .interactionScreenOpened
            }.count,
            todayCharacterTapCount: todayEvents.filter {
                $0.eventType == .characterTapped
            }.count,
            userActionEvents: events,
            resolvedKeptUrgeIDs: keptUrges.map(\.id)
        )
    }

    private func appDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let startDay = AppDay.startOfDay(for: start, calendar: calendar)
        let endDay = AppDay.startOfDay(for: end, calendar: calendar)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }
}
