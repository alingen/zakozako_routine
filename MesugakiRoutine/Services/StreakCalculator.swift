import Foundation

/// ルーティンの継続日数を計算する共通ロジック。
/// Home画面・記録画面・イベント解放条件で同じ数え方を使うためにここに集約する。
enum StreakCalculator {
    /// いずれかのルーティンを完了した日を「達成日」として、連続して達成している日数を数える。
    /// 今日すでに達成していれば今日を起点に、まだなら昨日を起点に、途切れるまで遡る。
    /// 達成日が1日も無ければ 0 を返す。
    static func currentStreak(
        sessions: [RoutineSession],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Int {
        let achievedDays = Set(
            sessions
                .filter { $0.status == .completed }
                .compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) }
        )
        let today = calendar.startOfDay(for: now)

        var cursor = today
        if !achievedDays.contains(today) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while achievedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}
