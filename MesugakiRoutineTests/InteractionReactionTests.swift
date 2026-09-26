import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class InteractionReactionTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        return calendar
    }
    private var now: Date { date(27, 12) }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute))!
    }
    private func offset(_ days: Int, from date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date)!
    }
    private func fact(_ completed: Date?, start: Date? = nil, end: Date? = nil, id: UUID = UUID()) -> RoutinePeriodFact {
        let day = AppDay.startOfDay(for: start ?? completed ?? now, calendar: calendar)
        return RoutinePeriodFact(routineID: id, periodStart: start ?? day,
            periodEnd: end ?? offset(1, from: day), completedAt: completed)
    }
    private func context(
        _ facts: [RoutinePeriodFact] = [], total: Int = 0, completed: Int = 0,
        events: [UserActionEvent] = [], now: Date? = nil
    ) -> ReactionContext {
        let now = now ?? self.now
        let day = AppDay.startOfDay(for: now, calendar: calendar)
        let dates = facts.compactMap(\.completedAt).filter { $0 <= now }
        let todayEvents = events.filter { $0.occurredAt >= day && $0.occurredAt <= now }
        let opens = events.filter { $0.eventType == .appOpened }.map(\.occurredAt).sorted()
        let gap: Int? = opens.count < 2 ? nil : calendar.dateComponents([.day],
            from: AppDay.startOfDay(for: opens[opens.count - 2], calendar: calendar),
            to: AppDay.startOfDay(for: opens.last!, calendar: calendar)).day
        return ReactionContext(
            activeRoutineIDs: [], todayRoutineIDs: (0..<total).map { _ in UUID() },
            todayCompletedRoutineIDs: (0..<completed).map { _ in UUID() }, routinePeriodFacts: facts,
            currentStreak: RoutineStreak.overallStreak(completionDates: dates, now: now, calendar: calendar),
            bestStreak: RoutineStreak.overallBestStreak(completionDates: dates, calendar: calendar),
            totalCompletionDays: Set(dates.map { AppDay.startOfDay(for: $0, calendar: calendar) }).count,
            lastCompletionAt: dates.max(), allCompletedAt: total > 0 && total == completed ? dates.max() : nil,
            daysSinceLastCompletion: nil, todayProhibitionOutcome: nil,
            todayProhibitionUrgeCount: todayEvents.filter { $0.eventType == .prohibitionUrge }.count,
            todayProhibitionFailCount: todayEvents.filter { $0.eventType == .prohibitionFailed }.count,
            lastProhibitionUrgeAt: events.last { $0.eventType == .prohibitionUrge }?.occurredAt,
            lastProhibitionFailedAt: events.last { $0.eventType == .prohibitionFailed }?.occurredAt,
            lastAppOpenAt: opens.last, previousAppOpenAt: opens.dropLast().last,
            daysSinceLastAppOpen: nil, daysSincePreviousAppOpen: gap,
            todayInteractionOpenCount: todayEvents.filter { $0.eventType == .interactionScreenOpened }.count,
            todayCharacterTapCount: todayEvents.filter { $0.eventType == .characterTapped }.count,
            userActionEvents: events
        )
    }
    private func matches(_ context: ReactionContext, trigger: ReactionTrigger = .interactionOpened, now: Date? = nil) throws -> Set<String> {
        let content = try StoryContentRepository()
        return Set(ReactionConditionEvaluator.matches(conditions: content.reactionConditions,
            context: context, trigger: trigger, now: now ?? self.now, calendar: calendar).map { $0.condition.id })
    }
    private func condition(_ id: String, priority: Int = 60, active: Bool = true) -> ReactionCondition {
        ReactionCondition(conditionId: id, label: id, triggerType: "derived", conditionKey: "routinePeriodFacts",
            operator: "derived", value: "", priority: priority, active: active)
    }
    private func line(_ id: String, condition: String, weight: Int = 1, active: Bool = true) -> ReactionLine {
        ReactionLine(lineId: id, conditionId: condition, text: "A[br]B", strength: "strong",
            premiumOnly: true, weight: weight, active: active)
    }
    private func defaults() -> UserDefaults {
        let suite = "InteractionReactionTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testRoutineProgressAndCompletionTiming() throws {
        XCTAssertTrue(try matches(context(total: 4)).contains("routine_none_completed"))
        XCTAssertFalse(try matches(context()).contains("routine_none_completed"))
        let one = context([fact(now)], total: 4, completed: 1)
        XCTAssertTrue(try matches(one).isSuperset(of: ["routine_one_completed", "routine_today_first_completed", "routine_completed_just_now", "routine_first_completion"]))
        let half = context([fact(now), fact(now)], total: 4, completed: 2)
        XCTAssertTrue(try matches(half).isSuperset(of: ["routine_half_completed", "routine_remaining_two"]))
        XCTAssertTrue(try matches(context([fact(now)], total: 2, completed: 1)).contains("routine_remaining_one"))
        XCTAssertTrue(try matches(context([fact(now)], total: 1, completed: 1)).contains("routine_all_completed"))
        XCTAssertFalse(try matches(one, now: now.addingTimeInterval(121)).contains("routine_completed_just_now"))
        XCTAssertFalse(try matches(one, trigger: .characterTapped).contains("routine_completed_just_now"))
        let early = date(27, 8)
        XCTAssertTrue(try matches(context([fact(early)], total: 1, completed: 1)).contains("routine_all_completed_early"))
        let late = date(28, 3)
        XCTAssertTrue(try matches(context([fact(late)], total: 1, completed: 1, now: late), now: late).contains("routine_all_completed_late"))
    }

    func testCompletionDatesAreNotDuplicatedAcrossWeeklyPeriodOrRuleSegments() throws {
        let id = UUID()
        let yesterday = date(26, 10)
        let week = fact(yesterday, start: date(21, 4), end: date(28, 4), id: id)
        let result = try matches(context([week], total: 1, completed: 1))
        XCTAssertTrue(result.contains("routine_none_completed"))
        XCTAssertFalse(result.contains("routine_one_completed"))
        XCTAssertFalse(result.contains("streak_1"))
        let duplicates = [fact(now, id: id), fact(now, id: id)]
        XCTAssertTrue(try matches(context(duplicates, total: 1, completed: 1)).contains("routine_one_completed"))
        XCTAssertTrue(try matches(context([fact(yesterday), fact(now), fact(now)], total: 2, completed: 2)).contains("routine_yesterday_more"))
        XCTAssertTrue(try matches(context([fact(yesterday)], total: 2)).contains("routine_yesterday_less"))
    }

    func testAllStreakMilestonesAndNoYesterdayCarryover() throws {
        for days in [1, 2, 3, 4, 7, 10, 14, 30, 50, 100] {
            let facts = (0..<days).map { fact(offset(-$0, from: now)) }
            let actual = try matches(context(facts, total: 1, completed: 1))
            XCTAssertTrue(actual.contains("streak_\(days)"), "Day \(days)")
            XCTAssertTrue(actual.contains("streak_new_best"))
            if [10, 30, 50, 100].contains(days) { XCTAssertTrue(actual.contains("total_completion_milestone")) }
            XCTAssertFalse(try matches(context(facts, total: 1, now: offset(1, from: now)), now: offset(1, from: now)).contains("streak_\(days)"))
        }
        let oldRun = (10..<14).map { fact(offset(-$0, from: now)) }
        let currentRun = (0..<3).map { fact(offset(-$0, from: now)) }
        let actual = try matches(context(oldRun + currentRun, total: 1, completed: 1))
        XCTAssertTrue(actual.contains("streak_one_to_best"))
        XCTAssertFalse(actual.contains("streak_new_best"))
    }

    func testBrokenAndReturningStreaksOnlyAtRelevantTime() throws {
        let prior = (2..<9).map { fact(offset(-$0, from: now)) }
        XCTAssertTrue(try matches(context(prior, total: 1)).isSuperset(of: ["streak_broken", "streak_long_broken"]))
        XCTAssertFalse(try matches(context(prior, total: 1, now: offset(1, from: now)), now: offset(1, from: now)).contains("streak_broken"))
        XCTAssertTrue(try matches(context(prior + [fact(now)], total: 1, completed: 1)).contains("streak_return_next_day"))
        XCTAssertTrue(try matches(context([fact(offset(-4, from: now)), fact(now)], total: 1, completed: 1)).contains("streak_return_after_days"))
        let events = [UserActionEvent(eventType: .appOpened, occurredAt: offset(-3, from: now)),
                      UserActionEvent(eventType: .appOpened, occurredAt: now)]
        XCTAssertTrue(try matches(context(events: events)).contains("app_return_after_absence"))
        XCTAssertFalse(try matches(context(events: events), trigger: .characterTapped).contains("app_return_after_absence"))
    }

    func testFullCompletionRequiresSevenDaysAndEveryApplicableRoutine() throws {
        let seven = (0..<7).map { fact(offset(-$0, from: now)) }
        XCTAssertTrue(try matches(context(seven, total: 1, completed: 1)).contains("routine_full_streak"))
        XCTAssertFalse(try matches(context(Array(seven.prefix(6)), total: 1, completed: 1)).contains("routine_full_streak"))
        XCTAssertFalse(try matches(context(seven + [fact(nil, start: offset(-2, from: date(27, 4)))], total: 1, completed: 1)).contains("routine_full_streak"))
        let completedThisWeek = fact(now, start: offset(-6, from: date(27, 4)), end: date(28, 4))
        XCTAssertFalse(try matches(context([completedThisWeek], total: 1, completed: 1)).contains("routine_full_streak"))
    }

    func testProhibitionEventsAreExactTriggersAndSeparateFromLaterState() throws {
        let urge = UserActionEvent(eventType: .prohibitionUrge, targetType: .prohibition, targetID: UUID(), occurredAt: now)
        let failed = UserActionEvent(eventType: .prohibitionFailed, occurredAt: now)
        let ctx = context(events: [urge, failed])
        XCTAssertEqual(try matches(ctx, trigger: .action(urge.id)), ["prohibition_urge"])
        XCTAssertEqual(try matches(ctx, trigger: .action(failed.id)), ["prohibition_failed"])
        let opened = try matches(ctx)
        XCTAssertFalse(opened.contains("prohibition_failed"))
        XCTAssertFalse(opened.contains("prohibition_urge"))
        XCTAssertTrue(opened.contains("prohibition_one_failed"))
        XCTAssertTrue(opened.contains("interaction_after_prohibition_failed"))
        XCTAssertTrue(try matches(ctx, trigger: .action(failed.id), now: now.addingTimeInterval(121)).isEmpty)
        let failures = [UserActionEvent(eventType: .prohibitionFailed, occurredAt: date(27, 7)),
                        UserActionEvent(eventType: .prohibitionFailed, occurredAt: date(27, 8))]
        XCTAssertTrue(try matches(context(events: failures)).isSuperset(of: ["prohibition_multiple_failed", "prohibition_failed_early"]))
    }

    func testUrgeKeptUsesSameTargetAndOnlyFinalizedPreviousDay() throws {
        let container = try ModelContainer(for: Routine.self, BlockedBehavior.self, UserActionEvent.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let model = container.mainContext
        let kept = BlockedBehavior(title: "守れた", createdAt: date(26, 4))
        let lost = BlockedBehavior(title: "破った", createdAt: date(26, 4))
        model.insert(kept)
        model.insert(lost)
        try model.save()
        let repo = BlockedBehaviorRepository(context: model)
        let keptEvent = try repo.recordUrge(kept, now: date(26, 12))
        try repo.recordUrge(lost, now: date(26, 12))
        try repo.recordFailure(lost, now: date(26, 13), calendar: calendar)
        let provider = ReactionContextProvider(context: model)
        XCTAssertTrue(try provider.current(now: date(26, 23), calendar: calendar).resolvedKeptUrgeIDs.isEmpty)
        let actual = try provider.current(now: now, calendar: calendar)
        XCTAssertEqual(actual.resolvedKeptUrgeIDs, [keptEvent.id])
        XCTAssertTrue(try matches(actual).contains("prohibition_urge_then_kept"))
    }

    func testInteractionCountsAndTriggerScopes() throws {
        let opened = UserActionEvent(eventType: .interactionScreenOpened, occurredAt: now)
        XCTAssertTrue(try matches(context(total: 1, events: [opened])).isSuperset(of: ["interaction_first_today", "interaction_before_completion"]))
        XCTAssertFalse(try matches(context(total: 1, events: [opened]), trigger: .characterTapped).contains("interaction_first_today"))
        let visits = (0..<3).map { _ in UserActionEvent(eventType: .interactionScreenOpened, occurredAt: now) }
        let taps = (0..<3).map { _ in UserActionEvent(eventType: .characterTapped, occurredAt: now) }
        let ctx = context([fact(now)], total: 1, completed: 1, events: visits + taps)
        XCTAssertTrue(try matches(ctx).isSuperset(of: ["interaction_many_today", "interaction_after_completion", "interaction_after_all_completed"]))
        XCTAssertTrue(try matches(ctx, trigger: .characterTapped).contains("character_many_taps"))
        XCTAssertFalse(try matches(ctx).contains("character_many_taps"))
    }

    func testLocalTimeAndFourAMDayBoundary() throws {
        for (hour, id) in [(8, "morning_zero"), (12, "noon_zero"), (18, "evening_zero"),
                           (2, "late_night_remaining"), (5, "early_morning_access"), (1, "late_night_access")] {
            let time = date(27, hour)
            XCTAssertTrue(try matches(context(total: 1, now: time), now: time).contains(id), id)
        }
        let before = date(28, 3, 59) // 暦は月曜、アプリ日は日曜
        let after = date(28, 4)
        XCTAssertFalse(try matches(context(now: before), now: before).contains("monday"))
        XCTAssertTrue(try matches(context(now: after), now: after).contains("monday"))
        XCTAssertFalse(try matches(context(total: 1, now: before), now: before).contains("early_morning_access"))
        XCTAssertTrue(try matches(context(total: 1, now: after), now: after).contains("early_morning_access"))
    }

    func testPriorityTieStrongPremiumAndPersistedConsumption() throws {
        let ctx = context([fact(now)], total: 4, completed: 1)
        let conditions = [condition("routine_one_completed", priority: 80),
                          condition("routine_first_completion", priority: 80),
                          condition("routine_yesterday_more", priority: 20)]
        let lines = conditions.map { line($0.id, condition: $0.id) }
        for (random, expected) in [(0.0, "routine_one_completed"), (0.99, "routine_first_completion")] {
            let store = defaults()
            let service = InteractionReactionService(defaults: store)
            let selected = service.select(conditions: conditions, lines: lines, interactions: [], context: ctx,
                trigger: .interactionOpened, now: now, calendar: calendar, randomUnit: { random })
            XCTAssertEqual(selected?.id, expected)
            XCTAssertEqual(selected?.displayText, "A\nB") // strong + premiumOnly == true
            let reopened = InteractionReactionService(defaults: store)
            let next = reopened.select(conditions: conditions, lines: lines, interactions: [], context: ctx,
                trigger: .interactionOpened, now: now, calendar: calendar, randomUnit: { random })
            XCTAssertNotEqual(selected?.id, next?.id)
            XCTAssertNotEqual(next?.id, "routine_yesterday_more")
        }
    }

    func testWeightAndInactiveLines() {
        let ctx = context([fact(now)], total: 2, completed: 1)
        let conditions = [condition("routine_one_completed")]
        let lines = [line("light", condition: "routine_one_completed"),
                     line("heavy", condition: "routine_one_completed", weight: 3),
                     line("off", condition: "routine_one_completed", weight: 999, active: false)]
        for (random, expected) in [(0.0, "light"), (0.9, "heavy")] {
            let selected = InteractionReactionService(defaults: defaults()).select(
                conditions: conditions, lines: lines, interactions: [], context: ctx,
                trigger: .characterTapped, now: now, calendar: calendar, randomUnit: { random })
            XCTAssertEqual(selected?.id, expected)
        }
        XCTAssertTrue(ReactionConditionEvaluator.matches(conditions: [condition("routine_one_completed", active: false)],
            context: ctx, trigger: .characterTapped, now: now, calendar: calendar).isEmpty)
    }

    func testDailyPoolStaysAtThreeAndRotatesAtFourAMAvoidingYesterday() {
        let store = defaults()
        let comments = (0..<9).map { InteractionComment(id: "i\($0)", text: "line \($0)") }
        func selected(_ time: Date, random: Double) -> String? {
            InteractionReactionService(defaults: store).select(conditions: [], lines: [], interactions: comments,
                context: context(now: time), trigger: .characterTapped, now: time, calendar: calendar,
                randomUnit: { random })?.id
        }
        var today = Set<String>()
        for _ in 0..<3 { today.insert(selected(now, random: 0)!) }
        today.insert(selected(date(28, 3, 59), random: 0.99)!)
        XCTAssertEqual(today, ["i0", "i1", "i2"])
        var next = Set<String>()
        for _ in 0..<3 { next.insert(selected(date(28, 4), random: 0)!) }
        next.insert(selected(date(28, 4, 1), random: 0.99)!)
        XCTAssertEqual(next, ["i3", "i4", "i5"])
        XCTAssertTrue(today.isDisjoint(with: next))
    }

    func testSharedMarkersKeepSlashesAndSpaces() {
        XCTAssertEqual("A[br]B[sp]C/D".replacingStoryTextMarkers(), "A\nB C/D")
        XCTAssertEqual(ADVTextLayout.formatted("A[br]B[sp]C/D"), "A\nB C/D")
        XCTAssertEqual(InteractionComment(id: "x", text: "A[br]B").displayText, "A\nB")
    }
}
