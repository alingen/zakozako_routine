import Foundation

/// 「約束」「やらないこと」共通の集計期間。ユーザーは作成時に「1日 / 1週間のうち / 1ヶ月のうち」から選ぶ。
enum HabitPeriod: String, Codable, CaseIterable, Identifiable {
    case day
    case week
    case month

    var id: String { rawValue }

    /// 編集画面のピッカーに出す表記。
    var pickerLabel: String {
        switch self {
        case .day: return "1日"
        case .week: return "1週間のうち"
        case .month: return "1ヶ月のうち"
        }
    }

    /// カードの消費/達成状況に添える見出し。
    var currentUnitLabel: String {
        switch self {
        case .day: return "今日"
        case .week: return "今週"
        case .month: return "今月"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    /// この期間で「対象曜日」の指定が意味を持つか(1日のときだけ)。
    var supportsWeekdaySelection: Bool { self == .day }

    /// 指定日を含む期間ウィンドウ [start, end)。日付境界は 0時ではなく `AppDay.startHour`(既定4時)。
    func window(containing day: Date, calendar: Calendar = .current) -> DateInterval {
        let anchored = AppDay.anchor(day, calendar: calendar)
        guard let interval = calendar.dateInterval(of: calendarComponent, for: anchored) else {
            let start = AppDay.startOfDay(for: day, calendar: calendar)
            return DateInterval(start: start, duration: 86_400)
        }
        let start = calendar.date(byAdding: .hour, value: AppDay.startHour, to: interval.start) ?? interval.start
        let end = calendar.date(byAdding: .hour, value: AppDay.startHour, to: interval.end) ?? interval.end
        return DateInterval(start: start, end: end)
    }
}
