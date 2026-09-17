import Foundation

/// CMSの日付メタデータから、そのアプリ日に表示する「今日の会話」を選ぶ。
/// `calendar_date` の完全一致を優先し、なければ毎年繰り返す
/// `calendar_month_day` を使う。継続日数や初回利用日には依存しない。
enum DailyConversationSchedule {
    static func scenario(
        on date: Date = .now,
        from scenarios: [StoryScenario],
        calendar: Calendar = .current
    ) -> StoryScenario? {
        let calendarDate = dateKey(on: date, format: "yyyy-MM-dd", calendar: calendar)
        if let exact = scenarios.first(where: { $0.calendarDate == calendarDate }) {
            return exact
        }

        let calendarMonthDay = dateKey(on: date, format: "MM-dd", calendar: calendar)
        return scenarios.first { $0.calendarMonthDay == calendarMonthDay }
    }

    static func playbackKey(
        on date: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        "daily:\(dateKey(on: date, format: "yyyy-MM-dd", calendar: calendar))"
    }

    private static func dateKey(
        on date: Date,
        format: String,
        calendar: Calendar
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: AppDay.anchor(date, calendar: calendar))
    }
}
