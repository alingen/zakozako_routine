import Foundation

/// Home の約束グリッドに出す「現在の期間の進捗」。
struct RoutineTodayProgress {
    let fraction: Double
    let done: Int
    let target: Int
    /// 現在の期間の目標を達成しているか。
    let isCompletedToday: Bool

    /// 「2 / 3回」の内訳を出すべきか(目標2回以上・未達成のとき)。
    var showsCountBreakdown: Bool { target > 1 && !isCompletedToday }
}

extension Routine {
    func todayProgress(now: Date = .now, calendar: Calendar = .current) -> RoutineTodayProgress {
        let done = progressCount(now: now, calendar: calendar)
        let target = targetCount
        return RoutineTodayProgress(
            fraction: min(Double(done) / Double(target), 1),
            done: done,
            target: target,
            isCompletedToday: done >= target
        )
    }
}

/// 1つの約束の「何日連続で達成しているか」を `progressEvents` から計算する(保存値は持たない)。
///
/// - 期間が「1日」: 対象曜日だけを歩幅に、直近の対象日から遡って連続達成日数を数える。
///   対象外の曜日はスキップ。今日が対象日でまだ未達成なら今日は保留にして前の対象日から数える。
/// - 期間が「1週間/1ヶ月のうち」: すべての日を歩幅に、その日を含む期間が(その日終了時点で)
///   目標に達していた日が連続している数を数える。
enum RoutineStreak {
    static func currentStreak(
        routine: Routine,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        let weekdayScoped = routine.period == .day && !routine.activeWeekdayValues.isEmpty
        let targetWeekdays: Set<Int> = weekdayScoped ? Set(routine.activeWeekdayValues) : Set(1...7)

        func isCounted(_ day: Date) -> Bool {
            targetWeekdays.contains(calendar.component(.weekday, from: day))
        }
        func previousCounted(before day: Date) -> Date? {
            var cursor = day
            for _ in 0..<9 {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
                cursor = previous
                if isCounted(cursor) { return cursor }
            }
            return nil
        }

        let anchor: Date?
        if isCounted(today) {
            anchor = routine.wasCompleteOn(day: today, now: now, calendar: calendar)
                ? today
                : previousCounted(before: today)
        } else {
            anchor = previousCounted(before: today)
        }

        var streak = 0
        var cursor = anchor
        var safety = 0
        while let day = cursor,
              routine.wasCompleteOn(day: day, now: now, calendar: calendar),
              safety < 4000 {
            streak += 1
            cursor = previousCounted(before: day)
            safety += 1
        }
        return streak
    }

    /// 「いずれかの約束をその日達成した」日が今日(または昨日)から連続している数。記録タブの全体streak用。
    static func overallStreak(
        routines: [Routine],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let today = calendar.startOfDay(for: now)
        func anyCompleteOn(_ day: Date) -> Bool {
            routines.contains { $0.wasCompleteOn(day: day, now: now, calendar: calendar) }
        }

        var cursor = today
        if !anyCompleteOn(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        var safety = 0
        while anyCompleteOn(cursor), safety < 4000 {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            safety += 1
        }
        return streak
    }
}
