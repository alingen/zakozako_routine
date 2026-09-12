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

/// 1つの約束を何期間（日／週／月）連続で達成しているかを計算する。
/// 進行中の期間が未達でも、期限までは直前までの連続記録を維持する。
enum RoutineStreak {
    static func currentStreak(
        routine: Routine,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        RoutineYearStatisticsCalculator.currentStreak(
            for: routine,
            now: now,
            calendar: calendar
        )
    }

    /// 「いずれかの約束をその日達成した」日が今日(または昨日)から連続している数。記録タブの全体streak用。
    static func overallStreak(
        routines: [Routine],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let completionDates = routines.flatMap {
            RoutineYearStatisticsCalculator.completionDates(
                for: $0,
                now: now,
                calendar: calendar
            )
        }
        return overallStreak(
            completionDates: completionDates,
            now: now,
            calendar: calendar
        )
    }

    static func overallStreak(
        completionDates: [Date],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let today = AppDay.startOfDay(for: now, calendar: calendar)
        let completionDays = Set(
            completionDates.map {
                AppDay.startOfDay(for: $0, calendar: calendar)
            }
        )
        func anyCompleteOn(_ day: Date) -> Bool { completionDays.contains(day) }

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
