import Foundation

/// 1つの Routine を「何回連続で達成しているか」を、履歴(RoutineSession)から計算する。
///
/// アプリ全体の継続日数(`StreakCalculator`)とは**別物**。あちらはイベント解放条件
/// (`EventCondition.minStreakDays`)に使われているため変更しない。こちらは Home の
/// ルーティン行に出す「○日継続中！」専用。
///
/// 数え方:
/// - 対象曜日だけを歩幅にして直近の対象日から遡り、「達成した対象日」が連続している数を返す。
/// - 対象外の曜日はスキップする(streak を途切れさせない)。
/// - 今日が対象日でまだ未達成なら、今日は「保留」として無視し、前の対象日から数える
///   (＝日が終わっていないので途切れさせない。完了すれば伸びる)。
/// - `Routine.currentStreakDays` のような保存値は持たず、毎回履歴から計算する。
enum RoutineStreakCalculator {
    static func currentStreak(
        routine: Routine,
        sessions: [RoutineSession],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let targetWeekdays: Set<Int> = routine.activeWeekdayValues.isEmpty
            ? Set(1...7)
            : Set(routine.activeWeekdayValues)

        var achievedDays = Set<Date>()
        for session in sessions where session.routineId == routine.id && session.status == .completed {
            if let completedAt = session.completedAt {
                achievedDays.insert(calendar.startOfDay(for: completedAt))
            }
        }
        guard !achievedDays.isEmpty else { return 0 }

        let today = calendar.startOfDay(for: now)

        func isTargetDay(_ day: Date) -> Bool {
            targetWeekdays.contains(calendar.component(.weekday, from: day))
        }

        func previousTargetDay(before day: Date) -> Date? {
            var cursor = day
            for _ in 0..<7 {
                guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
                cursor = previous
                if isTargetDay(cursor) { return cursor }
            }
            return nil
        }

        // 起点: すでに「達成しているべき」直近の対象日。
        let anchor: Date?
        if isTargetDay(today) {
            anchor = achievedDays.contains(today) ? today : previousTargetDay(before: today)
        } else {
            anchor = previousTargetDay(before: today)
        }

        var streak = 0
        var cursor = anchor
        var safety = 0
        while let day = cursor, achievedDays.contains(day), safety < 3660 {
            streak += 1
            cursor = previousTargetDay(before: day)
            safety += 1
        }
        return streak
    }
}
