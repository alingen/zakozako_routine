import Foundation

enum ReactionTrigger: Equatable {
    case interactionOpened
    case characterTapped
    /// この呼び出しを起こした操作だけ。過去の失敗を即時イベントとして再生しない。
    case action(UUID)
}

struct ReactionMatch {
    let condition: ReactionCondition
    let consumptionKey: String
}

@MainActor
enum ReactionConditionEvaluator {
    /// ユーザー指定（2026-09-27）。「完全達成」は7アプリ日連続から。
    static let fullCompletionStreakDays = 7

    static func matches(
        conditions: [ReactionCondition], context: ReactionContext, trigger: ReactionTrigger,
        now: Date = .now, calendar: Calendar = .current
    ) -> [ReactionMatch] {
        let facts = Facts(context: context, now: now, calendar: calendar)
        return conditions.compactMap { condition in
            guard condition.active else { return nil }
            if condition.triggerType == "event" {
                guard case let .action(id) = trigger,
                      let event = context.userActionEvents.first(where: { $0.id == id }),
                      event.eventTypeRawValue == condition.conditionKey,
                      condition.operator == "event",
                      event.occurredAt <= now,
                      now.timeIntervalSince(event.occurredAt) <= 120 else { return nil }
                return ReactionMatch(condition: condition, consumptionKey: "\(condition.id):\(id)")
            }
            // 操作直後の枠には、その操作用に定義されたセリフだけを表示する。
            if case .action = trigger { return nil }
            guard facts.matches(condition, trigger: trigger) else { return nil }
            var key = condition.id
            // 新しい完了・失敗は同じ日でも別の出来事。元履歴の時刻/IDを参照するだけ。
            if ["routine_completed_just_now", "interaction_after_completion", "routine_today_first_completed"].contains(condition.id),
               let date = context.lastCompletionAt { key += ":\(date.timeIntervalSince1970)" }
            if condition.id == "interaction_after_all_completed", let date = context.allCompletedAt {
                key += ":\(date.timeIntervalSince1970)"
            }
            if condition.id == "interaction_after_prohibition_failed", let date = context.lastProhibitionFailedAt {
                key += ":\(date.timeIntervalSince1970)"
            }
            if condition.id == "prohibition_multiple_failed" { key += ":\(context.todayProhibitionFailCount)" }
            return ReactionMatch(condition: condition, consumptionKey: key)
        }
    }

    @MainActor
    private struct Facts {
        let context: ReactionContext
        let now: Date
        let calendar: Calendar
        let today: Date
        let yesterday: Date
        let completedDates: [Date]
        let completionDays: Set<Date>

        init(context: ReactionContext, now: Date, calendar: Calendar) {
            self.context = context
            self.now = now
            self.calendar = calendar
            today = AppDay.startOfDay(for: now, calendar: calendar)
            yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
            completedDates = context.routinePeriodFacts.compactMap(\.completedAt).filter { $0 <= now }
            completionDays = Set(completedDates.map { AppDay.startOfDay(for: $0, calendar: calendar) })
        }

        var completedToday: Bool { completionDays.contains(today) }
        var hour: Int { calendar.component(.hour, from: now) }
        var actualTodayCount: Int { completionCount(on: today) }
        var zeroToday: Bool { context.todayRoutineCount > 0 && actualTodayCount == 0 }

        func completionCount(on day: Date) -> Int {
            Set(context.routinePeriodFacts.filter {
                guard let date = $0.completedAt, date <= now else { return false }
                return AppDay.startOfDay(for: date, calendar: calendar) == day
            }.map(\.routineID)).count
        }

        func matches(_ condition: ReactionCondition, trigger: ReactionTrigger) -> Bool {
            let id = condition.id
            if id.hasPrefix("interaction_"), trigger != .interactionOpened { return false }
            if id == "character_many_taps", trigger != .characterTapped { return false }
            if id.hasPrefix("streak_"), condition.triggerType == "state", !completedToday { return false }
            if ["routine_remaining_one", "routine_remaining_two"].contains(id), context.todayRoutineCount == 0 { return false }

            if condition.triggerType == "state" {
                let value: Double
                switch condition.conditionKey {
                case "currentStreak": value = Double(context.currentStreak)
                case "remainingRoutineCount": value = Double(context.remainingRoutineCount)
                case "isAllCompleted": value = context.isAllCompleted ? 1 : 0
                case "todayProhibitionFailCount": value = Double(context.todayProhibitionFailCount)
                case "todayInteractionOpenCount": value = Double(context.todayInteractionOpenCount)
                case "todayCharacterTapCount": value = Double(context.todayCharacterTapCount)
                default: return false
                }
                return compare(value, condition: condition)
            }

            switch id {
            case "routine_none_completed", "interaction_before_completion": return zeroToday
            case "routine_one_completed": return context.todayRoutineCount > 0 && actualTodayCount == 1
            case "routine_today_first_completed":
                return trigger == .interactionOpened && actualTodayCount == 1 && recent(context.lastCompletionAt, seconds: 120)
            case "routine_half_completed":
                guard context.todayRoutineCount > 0 else { return false }
                let ratio = Double(context.todayCompletedCount) / Double(context.todayRoutineCount)
                return (0.4...0.6).contains(ratio)
            case "routine_all_completed_early", "routine_all_completed_late":
                return context.isAllCompleted && todayContains(context.allCompletedAt)
                    && timeMatches(context.allCompletedAt, range: condition.value)
            case "routine_completed_just_now", "interaction_after_completion":
                return trigger == .interactionOpened && recent(context.lastCompletionAt, range: condition.value)
            case "interaction_after_all_completed":
                return context.isAllCompleted && recent(context.allCompletedAt, range: condition.value)
            case "interaction_after_prohibition_failed":
                return recent(context.lastProhibitionFailedAt, range: condition.value)
            case "routine_first_completion":
                return Dictionary(grouping: context.routinePeriodFacts, by: \.routineID).values.contains { facts in
                    todayContains(facts.compactMap(\.completedAt).min())
                }
            case "routine_yesterday_more":
                return context.todayRoutineCount > 0 && actualTodayCount > completionCount(on: yesterday)
            case "routine_yesterday_less":
                return context.todayRoutineCount > 0 && actualTodayCount < completionCount(on: yesterday)
            case "streak_new_best":
                return completedToday && context.currentStreak > RoutineStreak.overallBestStreak(
                    completionDates: completedDates.filter { $0 < today }, calendar: calendar
                )
            case "streak_one_to_best":
                return completedToday && context.currentStreak == context.bestStreak - 1
            case "streak_broken", "streak_long_broken":
                // 昨日が最初の未達日。何日も前の中断を繰り返し指摘しない。
                guard !completedToday, !completionDays.contains(yesterday),
                      let last = completionDays.max(),
                      calendar.date(byAdding: .day, value: 2, to: last) == today else { return false }
                return id == "streak_broken" || run(endingOn: last) >= 7
            case "streak_return_next_day", "streak_return_after_days":
                guard completedToday, let previous = completionDays.filter({ $0 < today }).max() else { return false }
                let gap = calendar.dateComponents([.day], from: previous, to: today).day ?? 0
                return id == "streak_return_next_day" ? gap == 2 : gap >= 3
            case "total_completion_milestone":
                let milestones = condition.value.split(separator: "/").compactMap { Int($0) }
                return completedToday && milestones.contains(context.totalCompletionDays)
            case "routine_full_streak": return fullCompletionRun() >= fullCompletionStreakDays
            case "prohibition_urge_then_kept": return !context.resolvedKeptUrgeIDs.isEmpty
            case "prohibition_failed_early":
                return todayContains(context.lastProhibitionFailedAt) && timeMatches(context.lastProhibitionFailedAt, range: condition.value)
            case "app_return_after_absence":
                guard trigger == .interactionOpened, recent(context.lastAppOpenAt, seconds: 120),
                      let days = context.daysSincePreviousAppOpen else { return false }
                return compare(Double(days), condition: condition)
            // 通常会話の既存時間帯に合わせる（4–12 / 12–17 / 17–22）。
            case "morning_zero": return zeroToday && (4..<12).contains(hour)
            case "noon_zero": return zeroToday && (12..<17).contains(hour)
            case "evening_zero": return zeroToday && (17..<22).contains(hour)
            case "late_night_remaining": return hour < 4 && context.remainingRoutineCount > 0
            case "early_morning_access", "late_night_access": return timeMatches(now, range: condition.value)
            case "monday": return calendar.component(.weekday, from: AppDay.anchor(now, calendar: calendar)) == 2
            default: return false
            }
        }

        func fullCompletionRun() -> Int {
            guard context.isAllCompleted else { return 0 }
            var day = today
            var count = 0
            // 必要な7日だけ確認し、何年分も毎タップ走査しない。
            for _ in 0..<fullCompletionStreakDays {
                guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let applicable = context.routinePeriodFacts.filter { $0.periodStart < end && $0.periodEnd > day }
                guard !applicable.isEmpty, applicable.allSatisfy({ fact in
                    guard let date = fact.completedAt else { return false }
                    return date < end && date <= now
                }) else { break }
                count += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
            }
            return count
        }

        func run(endingOn day: Date) -> Int {
            var day = day
            var count = 0
            while completionDays.contains(day) {
                count += 1
                guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
                day = previous
            }
            return count
        }

        func todayContains(_ date: Date?) -> Bool {
            guard let date else { return false }
            return date >= today && date <= now
        }

        func recent(_ date: Date?, seconds: Double) -> Bool {
            guard let date, todayContains(date) else { return false }
            return (0...seconds).contains(now.timeIntervalSince(date))
        }

        func recent(_ date: Date?, range: String) -> Bool {
            let bounds = range.replacingOccurrences(of: "秒前", with: "").split(separator: "-").compactMap { Double($0) }
            guard bounds.count == 2, bounds[0] >= 0, bounds[0] <= bounds[1], let date, todayContains(date) else { return false }
            return (bounds[0]...bounds[1]).contains(now.timeIntervalSince(date))
        }

        func timeMatches(_ date: Date?, range: String) -> Bool {
            guard let date else { return false }
            let parts = range.split(separator: "-")
            let values = parts.compactMap { part -> Int? in
                let hm = part.split(separator: ":").compactMap { Int($0) }
                guard hm.count == 2, (0...23).contains(hm[0]), (0...59).contains(hm[1]) else { return nil }
                return hm[0] * 60 + hm[1]
            }
            guard values.count == 2 else { return false }
            let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
            // 06:59/03:59 はその分を含む。10:00/04:00 は次の時間帯の開始。
            let upper = values[1] + (values[1] % 60 == 59 ? 1 : 0)
            return values[0] <= upper ? (values[0]..<upper).contains(minute) : minute >= values[0] || minute < upper
        }

        func compare(_ value: Double, condition: ReactionCondition) -> Bool {
            let threshold = condition.value.uppercased() == "TRUE" ? 1.0
                : condition.value.uppercased() == "FALSE" ? 0.0 : Double(condition.value)
            guard let threshold else { return false }
            switch condition.operator {
            case "==": return value == threshold
            case "!=": return value != threshold
            case ">=": return value >= threshold
            case "<=": return value <= threshold
            case ">": return value > threshold
            case "<": return value < threshold
            default: return false
            }
        }
    }
}
