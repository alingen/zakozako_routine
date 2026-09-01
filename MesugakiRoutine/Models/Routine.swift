import Foundation
import SwiftData

/// ユーザーの「約束」(やること)。
///
/// 「1日 / 1週間のうち / 1ヶ月のうち に 〇回」のかたちで目標回数を持ち、Home でタップするたびに
/// 1回消費する(`progressEvents` にタイムスタンプを積む)。期間内の回数が目標に達したら「達成」。
/// ステップの概念は廃止し、回数に一本化した。
@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    /// グリッドの円の中に表示する SF Symbol 名。未設定(nil)なら何も表示しない。
    var iconName: String?

    /// 開始予定時刻(0時からの分数、0〜1439)。未設定ならnil。通知の起点に使う。
    var scheduledStartMinute: Int?

    /// 対象曜日(Weekdayのraw value)。**期間が「1日」のときだけ意味を持つ。**
    var activeWeekdayValues: [Int] = Weekday.allWeekdayValues

    /// 集計期間(生値)。既存データの軽量マイグレーションのため optional。nil は `.day`。
    var periodRawValue: String?
    /// 期間あたりの目標回数(生値)。nil / 1未満は 1。
    var targetCountValue: Int?
    /// 「1回やった」時刻のログ(生値)。nil は空配列。
    var progressEventsStore: [Date]?

    var period: HabitPeriod {
        get { periodRawValue.flatMap(HabitPeriod.init(rawValue:)) ?? .day }
        set { periodRawValue = newValue.rawValue }
    }
    var targetCount: Int {
        get { max(targetCountValue ?? 1, 1) }
        set { targetCountValue = max(newValue, 1) }
    }
    var progressEvents: [Date] {
        get { progressEventsStore ?? [] }
        set { progressEventsStore = newValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        scheduledStartMinute: Int? = nil,
        activeWeekdayValues: [Int] = Weekday.allWeekdayValues,
        iconName: String? = nil,
        period: HabitPeriod = .day,
        targetCount: Int = 1,
        progressEvents: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduledStartMinute = scheduledStartMinute
        self.activeWeekdayValues = activeWeekdayValues
        self.iconName = iconName
        self.periodRawValue = period.rawValue
        self.targetCountValue = targetCount
        self.progressEventsStore = progressEvents
    }

    // MARK: - 進捗

    /// 現在時刻を含む期間の、これまでの消費回数。
    func progressCount(now: Date = .now, calendar: Calendar = .current) -> Int {
        let window = period.window(containing: now, calendar: calendar)
        return progressEvents.filter { $0 >= window.start && $0 <= now }.count
    }

    /// 現在の期間の目標を達成しているか。
    func isComplete(now: Date = .now, calendar: Calendar = .current) -> Bool {
        progressCount(now: now, calendar: calendar) >= targetCount
    }

    /// 進捗円の塗り具合 0.0〜1.0。
    func fraction(now: Date = .now, calendar: Calendar = .current) -> Double {
        min(Double(progressCount(now: now, calendar: calendar)) / Double(targetCount), 1)
    }

    /// 指定日の終了時点(ただし未来は「今」まで)で、その日を含む期間が目標に達していたか。
    /// 連続達成日数の計算に使う。
    func wasCompleteOn(day: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let window = period.window(containing: day, calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? window.end
        let upperBound = min(window.end, dayEnd, now)
        let count = progressEvents.filter { $0 >= window.start && $0 < upperBound }.count
        return count >= targetCount
    }

    /// この期間で「対象曜日」を絞れるか。
    var supportsWeekdaySelection: Bool { period.supportsWeekdaySelection }

    /// 指定日にこの約束が「対象」か。1日の期間なら対象曜日、週/月なら常に対象。
    func isScheduled(on day: Date = .now, calendar: Calendar = .current) -> Bool {
        guard supportsWeekdaySelection else { return true }
        if activeWeekdayValues.isEmpty { return true }
        return activeWeekdayValues.contains(calendar.component(.weekday, from: day))
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}
