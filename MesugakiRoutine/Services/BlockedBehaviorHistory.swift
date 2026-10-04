import Foundation

/// 「やらないこと」の1日ごとの結果。
enum BlockedBehaviorDayOutcome: Equatable {
    /// 守れた。
    case kept
    /// 負けた。
    case lost
}

/// 勝ち・負けの日数。
struct BlockedBehaviorRecordCount: Equatable {
    var kept = 0
    var lost = 0

    var isEmpty: Bool { kept == 0 && lost == 0 }
}

/// 「やらないこと」の日ごとの勝ち負けを、ホームの自動判定と同じ基準で求める。
///
/// 日はカレンダーの日付(その日の0時)で指定し、日付の境界は `AppDay`(朝4時)に合わせる。
/// - 手動判定: その日の終わりまでに、期間内の回数が上限に達していれば負け。
///   今日はまだ決まっていないので、負けていなければ結果なし。
/// - スクリーンタイム: 拡張機能が記録した日だけ結果があり、監視できなかった日は結果なし。
struct BlockedBehaviorHistory {
    private let behavior: BlockedBehavior
    private let calendar: Calendar
    private let todayLabel: Date
    private let createdLabel: Date
    /// 卒業した項目は、最後に判定した日より後を数えない。
    private let lastEvaluatedLabel: Date?
    private let screenTimeFailedLabels: Set<Date>
    private let screenTimeVerifiedLabels: Set<Date>

    init(behavior: BlockedBehavior, now: Date = .now, calendar: Calendar = .current) {
        self.behavior = behavior
        self.calendar = calendar
        todayLabel = Self.calendarDay(of: now, calendar: calendar)
        createdLabel = Self.calendarDay(of: behavior.createdAt, calendar: calendar)
        lastEvaluatedLabel = behavior.masteredAt == nil
            ? nil
            : behavior.lastCheckInDate.map { Self.calendarDay(of: $0, calendar: calendar) }
        screenTimeFailedLabels = Set(
            behavior.screenTimeFailedDays.map { Self.calendarDay(of: $0, calendar: calendar) }
        )
        screenTimeVerifiedLabels = Set(
            behavior.screenTimeVerifiedDays.map { Self.calendarDay(of: $0, calendar: calendar) }
        )
    }

    /// 実時刻が属する日を、カレンダーの日付(0時)で返す。朝4時より前は前日扱い。
    static func calendarDay(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: AppDay.anchor(date, calendar: calendar))
    }

    /// カレンダーの日付の結果。まだ始まっていない日・未来・未確定・記録のない日は nil。
    func outcome(onCalendarDay day: Date) -> BlockedBehaviorDayOutcome? {
        let label = calendar.startOfDay(for: day)
        guard label >= createdLabel, label <= todayLabel else { return nil }
        if let lastEvaluatedLabel, label > lastEvaluatedLabel { return nil }

        switch behavior.trackingKind {
        case .screenTime:
            if screenTimeFailedLabels.contains(label) { return .lost }
            if screenTimeVerifiedLabels.contains(label) { return .kept }
            return nil
        case .manual:
            let dayStart = AppDay.start(ofCalendarDay: label, calendar: calendar)
            if behavior.exceededLimit(on: dayStart, calendar: calendar) { return .lost }
            return label < todayLabel ? .kept : nil
        }
    }

    /// `start`〜`end`(どちらもカレンダーの日付、両端を含む)の勝ち負けの日数。
    func count(from start: Date, through end: Date) -> BlockedBehaviorRecordCount {
        var result = BlockedBehaviorRecordCount()
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            switch outcome(onCalendarDay: day) {
            case .kept: result.kept += 1
            case .lost: result.lost += 1
            case nil: break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result
    }

    /// 今日を含む直近 `days` 日の勝ち負け。
    func recentCount(days: Int) -> BlockedBehaviorRecordCount {
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: todayLabel) ?? todayLabel
        return count(from: start, through: todayLabel)
    }

    /// `month` を含む月の勝ち負け。
    func count(inMonthContaining month: Date) -> BlockedBehaviorRecordCount {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: interval.end) else {
            return BlockedBehaviorRecordCount()
        }
        return count(from: interval.start, through: lastDay)
    }

    /// 今の連続日数。保存値は日付が変わるときに更新されるので、今日すでに負けていれば 0 にする。
    var currentStreak: Int {
        outcome(onCalendarDay: todayLabel) == .lost ? 0 : behavior.currentStreakDays
    }

    /// これまでで一番長く守れた日数。結果のない日は数えずに飛ばす(自動判定と同じ)。
    var longestStreak: Int {
        var best = 0
        var run = 0
        var day = createdLabel
        while day <= todayLabel {
            switch outcome(onCalendarDay: day) {
            case .kept:
                run += 1
                best = max(best, run)
            case .lost:
                run = 0
            case nil:
                break
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return max(best, behavior.currentStreakDays)
    }
}
