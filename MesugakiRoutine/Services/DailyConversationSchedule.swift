import Foundation

/// CMSに日付列がない現行の「今日の会話」を、初回利用日から1日1話で割り当てる。
///
/// 会話を開いたかどうかには依存せず日付で進むため、各話は独立コンテンツとして扱われる。
/// 将来CMSへ配信日列が追加された場合は、この型だけを差し替える。
enum DailyConversationSchedule {
    static func scenarioIndex(
        on date: Date = .now,
        anchorDate: Date,
        scenarioCount: Int,
        calendar: Calendar = .current
    ) -> Int? {
        guard scenarioCount > 0 else { return nil }
        let anchor = AppDay.startOfDay(for: anchorDate, calendar: calendar)
        let target = AppDay.startOfDay(for: date, calendar: calendar)
        let elapsed = max(
            calendar.dateComponents([.day], from: anchor, to: target).day ?? 0,
            0
        )
        return elapsed % scenarioCount
    }

    static func playbackKey(
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return "daily:\(formatter.string(from: AppDay.anchor(date, calendar: calendar)))"
    }
}
