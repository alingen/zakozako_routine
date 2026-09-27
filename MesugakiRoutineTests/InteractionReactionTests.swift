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
        XCTAssertTrue(try matches(one).isSuperset(of: ["routine_one_completed", "routine_today_first_completed", "routine_completed_just_now"]))
        XCTAssertFalse(try matches(one).contains("routine_first_completion"))
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

    func testHomeUsesProgressConditionsWithoutInteractionVisitConditions() throws {
        let visit = UserActionEvent(eventType: .interactionScreenOpened, occurredAt: now)
        let ctx = context([fact(now)], total: 2, completed: 1, events: [visit])
        let home = try matches(ctx, trigger: .homeUpdated)
        XCTAssertTrue(home.isSuperset(of: ["routine_one_completed", "routine_remaining_one",
            "routine_today_first_completed", "routine_completed_just_now"]))
        XCTAssertFalse(home.contains { $0.hasPrefix("interaction_") })
        XCTAssertFalse(home.contains("character_many_taps"))
        XCTAssertFalse(try matches(ctx, trigger: .homeUpdated, now: now.addingTimeInterval(121))
            .contains("routine_completed_just_now"))
        XCTAssertTrue(try matches(context(total: 2), trigger: .homeUpdated).contains("noon_zero"))
    }

    func testFirstCompletionRequiresTheRoutineJustCompletedAtHome() throws {
        let newRoutine = UUID()
        let existingRoutine = UUID()
        let ctx = context([
            fact(now.addingTimeInterval(-60), id: newRoutine),
            fact(offset(-1, from: now), id: existingRoutine),
            fact(now, id: existingRoutine),
        ], total: 2, completed: 2)
        XCTAssertTrue(try matches(ctx, trigger: .routineCompleted(newRoutine)).contains("routine_first_completion"))
        XCTAssertFalse(try matches(ctx, trigger: .routineCompleted(existingRoutine)).contains("routine_first_completion"))
        XCTAssertFalse(try matches(ctx, trigger: .routineCompleted(UUID())).contains("routine_first_completion"))
        for trigger in [ReactionTrigger.homeUpdated, .interactionOpened, .characterTapped] {
            // 当日中でも「初達成」の操作がなければ再生しない。
            XCTAssertFalse(try matches(ctx, trigger: trigger).contains("routine_first_completion"))
            XCTAssertFalse(try matches(ctx, trigger: trigger, now: date(27, 23)).contains("routine_first_completion"))
        }
        // 既存の「今達成」「今日最初の達成」は、新しい完了トリガーでも維持する。
        XCTAssertTrue(try matches(context([fact(now, id: newRoutine)], total: 2, completed: 1),
            trigger: .routineCompleted(newRoutine)).isSuperset(of: [
                "routine_first_completion", "routine_completed_just_now", "routine_today_first_completed",
            ]))
    }

    func testFirstCompletionUsesFourAMBoundaryAndExcludesFutureOrIncompleteRecords() throws {
        let id = UUID()
        let before = date(28, 3, 59)
        let ctx = context([fact(before, id: id)], total: 1, completed: 1, now: before)
        XCTAssertTrue(try matches(ctx, trigger: .routineCompleted(id), now: before).contains("routine_first_completion"))
        XCTAssertFalse(try matches(ctx, trigger: .routineCompleted(id), now: date(28, 4)).contains("routine_first_completion"))
        XCTAssertFalse(try matches(context([fact(now.addingTimeInterval(1), id: id)]),
            trigger: .routineCompleted(id)).contains("routine_first_completion"))
        XCTAssertFalse(try matches(context([fact(nil, id: id)]),
            trigger: .routineCompleted(id)).contains("routine_first_completion"))
        let previouslyCompleted = context([fact(date(26, 12), id: id), fact(now, id: id)], total: 1, completed: 1)
        XCTAssertFalse(try matches(previouslyCompleted, trigger: .routineCompleted(id)).contains("routine_first_completion"))
    }

    func testHomeFirstCompletionCannotLeakToOtherCompletionsOrOpening() {
        let newRoutine = UUID()
        let existingRoutine = UUID()
        let ctx = context([fact(now, id: newRoutine), fact(now, id: existingRoutine),
            fact(offset(-1, from: now), id: existingRoutine)], total: 2, completed: 2)
        let conditions = [condition("routine_first_completion", priority: 999)]
        let lines = [line("first", condition: "routine_first_completion")]
        let service = InteractionReactionService(defaults: defaults())
        func selected(_ routineID: UUID? = nil) -> String? {
            service.selectHomeReaction(candidates: ["routine_first_completion"],
                conditions: conditions, lines: lines, context: ctx, completedRoutineID: routineID,
                now: now, calendar: calendar)?.conditionID
        }
        XCTAssertNil(selected())
        XCTAssertNil(selected(existingRoutine))
        XCTAssertEqual(selected(newRoutine), "routine_first_completion")
        XCTAssertNil(selected(newRoutine)) // 達成の取り消し・再達成でも同日に繰り返さない。
    }

    func testHomeAndInteractionShareReactionConsumptionAndFallback() throws {
        let storage = defaults()
        let home = InteractionReactionService(defaults: storage)
        let interaction = InteractionReactionService(defaults: storage)
        let conditions = [condition("routine_none_completed")]
        let lines = [line("home_line", condition: "routine_none_completed")]
        let fallback = [InteractionComment(id: "daily", text: "通常会話")]
        let ctx = context(total: 1)
        let selected = home.select(conditions: conditions, lines: lines, interactions: fallback,
            context: ctx, trigger: .homeUpdated, now: now, calendar: calendar)
        XCTAssertEqual(selected?.id, "home_line")
        XCTAssertEqual(selected?.displayText, "A\nB")
        XCTAssertEqual(interaction.select(conditions: conditions, lines: lines, interactions: fallback,
            context: ctx, trigger: .interactionOpened, now: now, calendar: calendar)?.id, "daily")
        let tomorrow = offset(1, from: now)
        XCTAssertEqual(home.select(conditions: conditions, lines: lines, interactions: fallback,
            context: context(total: 1, now: tomorrow), trigger: .homeUpdated,
            now: tomorrow, calendar: calendar)?.id, "home_line")
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
            // 以前の記録がない連続は、自己ベスト更新として毎日は言わない。
            XCTAssertFalse(actual.contains("streak_new_best"))
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
                          condition("routine_today_first_completed", priority: 80),
                          condition("routine_yesterday_more", priority: 20)]
        let lines = conditions.map { line($0.id, condition: $0.id) }
        for (random, expected) in [(0.0, "routine_one_completed"), (0.99, "routine_today_first_completed")] {
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

    func testAllCompletedPopupUsesCMSAfterHomeAlreadyConsumedCondition() throws {
        let condition = try XCTUnwrap(StoryContentRepository().reactionConditions.first {
            $0.id == "routine_all_completed"
        })
        let lines = [line("first", condition: condition.id), line("second", condition: condition.id),
                     line("disabled", condition: condition.id, weight: 999, active: false)]
        let ctx = context([fact(now)], total: 1, completed: 1)
        let service = InteractionReactionService(defaults: defaults())
        XCTAssertEqual(service.select(conditions: [condition], lines: lines, interactions: [],
            context: ctx, trigger: .homeUpdated, now: now, calendar: calendar, randomUnit: { 0 })?.id, "first")
        let popup = service.selectAllCompletedReaction(conditions: [condition], lines: lines,
            context: ctx, now: now, calendar: calendar, randomUnit: { 0 })
        XCTAssertEqual(popup?.id, "second")
        XCTAssertEqual(popup?.displayText, "A\nB")
        XCTAssertNil(service.select(conditions: [condition], lines: lines, interactions: [],
            context: ctx, trigger: .interactionOpened, now: now, calendar: calendar))
    }

    func testAllCompletedPopupRequiresCompletionAndOnlyUsesEnabledMatchingLines() throws {
        var allDone = try XCTUnwrap(StoryContentRepository().reactionConditions.first {
            $0.id == "routine_all_completed"
        })
        let lines = [line("disabled", condition: allDone.id, active: false),
                     line("zero", condition: allDone.id, weight: 0),
                     line("light", condition: allDone.id),
                     line("heavy", condition: allDone.id, weight: 3),
                     line("unrelated", condition: "routine_first_completion", weight: 999)]
        let ctx = context([fact(now)], total: 1, completed: 1)
        for (random, expected) in [(0.0, "light"), (0.9, "heavy")] {
            XCTAssertEqual(InteractionReactionService(defaults: defaults()).selectAllCompletedReaction(
                conditions: [allDone, condition("routine_first_completion", priority: 999)], lines: lines,
                context: ctx, now: now, calendar: calendar, randomUnit: { random })?.id, expected)
        }
        let service = InteractionReactionService(defaults: defaults())
        for incomplete in [context(), context([fact(now)], total: 2, completed: 1)] {
            XCTAssertNil(service.selectAllCompletedReaction(conditions: [allDone], lines: lines,
                context: incomplete, now: now, calendar: calendar))
        }
        XCTAssertNil(service.selectAllCompletedReaction(conditions: [allDone], lines: Array(lines.prefix(2)),
            context: ctx, now: now, calendar: calendar))
        allDone = ReactionCondition(conditionId: allDone.id, label: allDone.label,
            triggerType: allDone.triggerType, conditionKey: allDone.conditionKey,
            operator: allDone.operator, value: allDone.value, priority: allDone.priority, active: false)
        XCTAssertNil(service.selectAllCompletedReaction(conditions: [allDone], lines: lines,
            context: ctx, now: now, calendar: calendar))
    }

    func testHomeReactionPicksHighestPriorityCandidateOncePerDay() throws {
        let conditions = try StoryContentRepository().reactionConditions
        let lines = [line("seven", condition: "streak_7"), line("three", condition: "streak_3"),
                     line("four", condition: "streak_4")]
        let milestones: Set<String> = ["streak_3", "streak_7"]
        let service = InteractionReactionService(defaults: defaults())

        let seven = context((0..<7).map { fact(offset(-$0, from: now)) }, total: 1, completed: 1)
        let first = service.selectHomeReaction(candidates: milestones, conditions: conditions, lines: lines,
            context: seven, now: now, calendar: calendar, randomUnit: { 0 })
        XCTAssertEqual(first?.comment.id, "seven")
        XCTAssertEqual(first?.conditionID, "streak_7")
        // 取り消してから達成し直しても、同じ日の同じ節目は出し直さない。
        XCTAssertNil(service.selectHomeReaction(candidates: milestones, conditions: conditions, lines: lines,
            context: seven, now: now, calendar: calendar))
        // 候補に入れていない条件(streak_4)は、合っていても選ばない。
        let four = context((0..<4).map { fact(offset(-$0, from: now)) }, total: 1, completed: 1)
        XCTAssertNil(InteractionReactionService(defaults: defaults()).selectHomeReaction(
            candidates: milestones, conditions: conditions, lines: lines, context: four, now: now, calendar: calendar))
    }

    func testHomeReactionReusableAndNonConsumingSelection() throws {
        let conditions = try StoryContentRepository().reactionConditions
        let lines = [line("done", condition: "routine_all_completed")]
        let ctx = context([fact(now)], total: 1, completed: 1)
        let service = InteractionReactionService(defaults: defaults())
        let candidates: Set<String> = ["routine_all_completed"]
        XCTAssertNotNil(service.selectHomeReaction(candidates: candidates, conditions: conditions, lines: lines,
            context: ctx, now: now, calendar: calendar))
        // 表示済みでも、reusable に入っていれば操作への返事として選べる。
        XCTAssertNil(service.selectHomeReaction(candidates: candidates, conditions: conditions, lines: lines,
            context: ctx, now: now, calendar: calendar))
        XCTAssertNotNil(service.selectHomeReaction(candidates: candidates, reusable: candidates,
            conditions: conditions, lines: lines, context: ctx, now: now, calendar: calendar))

        // consume: false なら表示済みにしない。
        let other = InteractionReactionService(defaults: defaults())
        XCTAssertNotNil(other.selectHomeReaction(candidates: candidates, consume: false, conditions: conditions,
            lines: lines, context: ctx, now: now, calendar: calendar))
        XCTAssertNotNil(other.selectHomeReaction(candidates: candidates, conditions: conditions, lines: lines,
            context: ctx, now: now, calendar: calendar))
    }

    func testNewBestOnlyOnTheDayThePreviousRecordIsBeaten() throws {
        // 以前の最長は4日(17〜20日)。現在の連続とは未達日を挟む。
        let oldRun = (0..<4).map { fact(offset(-7 - $0, from: now)) }
        func current(_ days: Int) -> [RoutinePeriodFact] { (0..<days).map { fact(offset(-$0, from: now)) } }
        XCTAssertFalse(try matches(context(oldRun + current(4), total: 1, completed: 1)).contains("streak_new_best"))
        XCTAssertTrue(try matches(context(oldRun + current(5), total: 1, completed: 1)).contains("streak_new_best"))
        XCTAssertFalse(try matches(context(oldRun + current(6), total: 1, completed: 1)).contains("streak_new_best"))
        // 過去の記録がない初回の連続では言わない。
        XCTAssertFalse(try matches(context(current(3), total: 1, completed: 1)).contains("streak_new_best"))
        // 過去に短い連続があっても、3日未満の記録更新は言わない。
        for previousBest in 1...2 {
            let shortRun = (0..<previousBest).map { fact(offset(-10 - $0, from: now)) }
            XCTAssertFalse(try matches(context(shortRun + current(previousBest + 1), total: 1, completed: 1))
                .contains("streak_new_best"))
        }
        let threeDayRun = (0..<3).map { fact(offset(-10 - $0, from: now)) }
        XCTAssertTrue(try matches(context(threeDayRun + current(4), total: 1, completed: 1)).contains("streak_new_best"))

        let beaten = oldRun + current(5)
        let beforeBoundary = date(28, 3, 59)
        let afterBoundary = date(28, 4)
        XCTAssertTrue(try matches(context(beaten, total: 1, completed: 1, now: beforeBoundary),
            now: beforeBoundary).contains("streak_new_best"))
        XCTAssertFalse(try matches(context(beaten, total: 1, now: afterBoundary),
            now: afterBoundary).contains("streak_new_best"))
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

    func testDisplayTargetsDoNotLeakIntoGeneralCommentsOrCompletionPopups() throws {
        let content = try StoryContentRepository()
        let allDone = try XCTUnwrap(content.reactionConditions.first { $0.id == "routine_all_completed" })
        let special = content.reactionLines.filter { $0.displayTarget == "home_idle_right" }
        XCTAssertEqual(special.count, 2)
        let ctx = context([fact(now)], total: 1, completed: 1)
        let service = InteractionReactionService(defaults: defaults())
        XCTAssertNil(service.select(conditions: [allDone], lines: special, interactions: [], context: ctx,
            trigger: .homeUpdated, now: now, calendar: calendar))
        XCTAssertNil(service.selectAllCompletedReaction(conditions: [allDone], lines: special,
            context: ctx, now: now, calendar: calendar))
        XCTAssertNil(service.selectHomeReaction(candidates: [allDone.id], conditions: [allDone],
            lines: special, context: ctx, now: now, calendar: calendar))
        XCTAssertNotNil(service.selectForPresentation(conditions: [allDone], lines: special,
            context: ctx, target: .idleRight, now: now, calendar: calendar))
        XCTAssertNil(service.selectForPresentation(conditions: [allDone], lines: special,
            context: context(total: 1), target: .idleRight, now: now, calendar: calendar))
    }

    func testRoutineAddedAndTimerFinishedRequireExactFreshAction() throws {
        let content = try StoryContentRepository()
        for (type, id, target) in [
            (UserActionEventType.routineAdded, "routine_added", ReactionDisplayTarget.routineAdded),
            (.routineTimerFinished, "routine_timer_finished", .general),
        ] {
            let event = UserActionEvent(eventType: type, targetType: .routine, targetID: UUID(), occurredAt: now)
            let ctx = context(total: 1, events: [event])
            XCTAssertEqual(try matches(ctx, trigger: .action(event.id)), [id])
            let service = InteractionReactionService(defaults: defaults())
            func select(_ trigger: ReactionTrigger, time: Date? = nil) -> ReactionLine? {
                service.selectForPresentation(conditions: content.reactionConditions, lines: content.reactionLines,
                    context: ctx, target: target, trigger: trigger, conditionID: id, routineTitle: "読書",
                    now: time ?? now, calendar: calendar)
            }
            XCTAssertEqual(select(.action(event.id))?.conditionId, id)
            XCTAssertNil(select(.homeUpdated))
            XCTAssertNil(select(.action(UUID())))
            XCTAssertNil(select(.action(event.id), time: now.addingTimeInterval(121)))
        }
    }

    func testMigratedPeeksRespectStateTemplateAndCompactLimits() throws {
        let content = try StoryContentRepository()
        let service = InteractionReactionService(defaults: defaults())
        let ctx = context(total: 2)
        let selected = try XCTUnwrap(service.selectForPresentation(
            conditions: content.reactionConditions, lines: content.reactionLines, context: ctx,
            target: .unfinishedPeek, routineTitle: "読書[br]", now: now, calendar: calendar))
        XCTAssertTrue(selected.displayText(routineTitle: "読書[br]").contains("読書[br]"))
        XCTAssertFalse(selected.displayText(routineTitle: "読書[br]").contains("{routine_title}"))
        XCTAssertNil(service.selectForPresentation(conditions: content.reactionConditions,
            lines: content.reactionLines, context: ctx, target: .unfinishedPeek, now: now, calendar: calendar))
        let compact = try XCTUnwrap(service.selectForPresentation(
            conditions: content.reactionConditions, lines: content.reactionLines, context: ctx,
            target: .unfinishedTopPeek, now: now, calendar: calendar))
        XCTAssertLessThanOrEqual(compact.displayText().count, 10)
        XCTAssertFalse(compact.displayText().contains("\n"))
        XCTAssertNil(service.selectForPresentation(conditions: content.reactionConditions,
            lines: content.reactionLines, context: context(), target: .unfinishedTopPeek, now: now, calendar: calendar))
    }

    func testPresentationSelectionHonorsDisabledConditionAndWeight() {
        var valid = line("valid", condition: "routine_one_completed")
        valid.displayTarget = ReactionDisplayTarget.idleAbove.rawValue
        var off = line("off", condition: valid.conditionId, active: false)
        off.displayTarget = valid.displayTarget
        var zero = line("zero", condition: valid.conditionId, weight: 0)
        zero.displayTarget = valid.displayTarget
        let service = InteractionReactionService(defaults: defaults())
        let ctx = context([fact(now)], total: 2, completed: 1)
        XCTAssertEqual(service.selectForPresentation(conditions: [condition(valid.conditionId)],
            lines: [off, zero, valid], context: ctx, target: .idleAbove,
            now: now, calendar: calendar)?.id, valid.id)
        XCTAssertNil(service.selectForPresentation(conditions: [condition(valid.conditionId, active: false)],
            lines: [valid], context: ctx, target: .idleAbove, now: now, calendar: calendar))
    }
}
