import Foundation
import SwiftData

/// ユーザーの「約束」(やること)。
///
/// 「1日 / 1週間のうち / 1ヶ月のうち に 〇回」のかたちで目標回数を持つ。
/// タイマー完了では1回ずつ、Home の完了ボタンでは現在期間が達成になる不足回数ぶんを
/// `progressEvents` に記録する。期間内の回数が目標に達したら「達成」。
@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    /// 「寝る前」「朝ごはんの後」など、この約束を始めるきっかけ。
    /// 通知時刻とは分けて保持し、未設定の既存データでは nil。
    var cueText: String?
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Home のカード先頭に表示する SF Symbol 名。未設定(nil)なら共通アイコンを表示する。
    var iconName: String?

    /// 開始予定時刻(0時からの分数、0〜1439)。未設定ならnil。通知の起点に使う。
    var scheduledStartMinute: Int?

    /// タイマーで取り組む目標分数。通常の約束では nil。
    var targetDurationMinutes: Int?

    /// 対象曜日(Weekdayのraw value)。**期間が「1日」のときだけ意味を持つ。**
    var activeWeekdayValues: [Int] = Weekday.allWeekdayValues

    /// SwiftDataへ保存する集計期間の生値。
    var periodRawValue: String
    /// 期間あたりの目標回数。
    var targetCountValue: Int
    /// 「1回やった」時刻のログ。
    var progressEventsStore: [Date]

    /// Home の完了ボタンが補ったログを、解除時に元へ戻すための印。
    /// Optional にして、既存ストアからの軽量移行でも値を持たない状態を表せるようにする。
    var homeCompletionRecordedAt: Date?
    var homeCompletionAddedCount: Int?

    /// 現在の回数・期間・対象曜日ルールを適用し始めた時刻。
    /// 設定変更時にだけ更新し、変更前後の進捗を混ぜない。
    var currentRuleStartedAt: Date

    /// 達成ルールを変更する前に確定した、期間ごとの統計結果。
    /// Data にしておくことで、集計用の値型をSwiftDataスキーマから独立させる。
    var progressStatisticsArchiveData: Data?

    var period: HabitPeriod {
        get { HabitPeriod(rawValue: periodRawValue) ?? .day }
        set { periodRawValue = newValue.rawValue }
    }
    var targetCount: Int {
        get { max(targetCountValue, 1) }
        set { targetCountValue = max(newValue, 1) }
    }
    var progressEvents: [Date] {
        get { progressEventsStore }
        set { progressEventsStore = newValue }
    }

    init(
        id: UUID = UUID(),
        title: String,
        cueText: String? = nil,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        scheduledStartMinute: Int? = nil,
        targetDurationMinutes: Int? = nil,
        activeWeekdayValues: [Int] = Weekday.allWeekdayValues,
        iconName: String? = nil,
        period: HabitPeriod = .day,
        targetCount: Int = 1,
        progressEvents: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.cueText = cueText
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduledStartMinute = scheduledStartMinute
        self.targetDurationMinutes = targetDurationMinutes.map { max($0, 1) }
        self.activeWeekdayValues = activeWeekdayValues
        self.iconName = iconName
        self.periodRawValue = period.rawValue
        self.targetCountValue = max(targetCount, 1)
        self.progressEventsStore = progressEvents
        self.homeCompletionRecordedAt = nil
        self.homeCompletionAddedCount = nil
        self.currentRuleStartedAt = createdAt
        self.progressStatisticsArchiveData = nil
    }

    // MARK: - 進捗

    /// 現在時刻を含む期間の、これまでの消費回数。
    func progressCount(now: Date = .now, calendar: Calendar = .current) -> Int {
        let window = period.window(containing: now, calendar: calendar)
        return progressEvents.filter {
            $0 >= max(window.start, currentRuleStartedAt) && $0 <= now
        }.count
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
    /// 連続達成日数の計算に使う。`day` は実時刻の一点でも、日付境界を跨がない範囲の値でもよい
    /// (呼び出し側でカレンダーのマス目を渡す場合は `AppDay.start(ofCalendarDay:)` を通すこと)。
    func wasCompleteOn(day: Date, now: Date = .now, calendar: Calendar = .current) -> Bool {
        let window = period.window(containing: day, calendar: calendar)
        let dayStart = AppDay.startOfDay(for: day, calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? window.end
        let upperBound = min(window.end, dayEnd, now)
        let count = progressEvents.filter {
            $0 >= max(window.start, currentRuleStartedAt) && $0 < upperBound
        }.count
        return count >= targetCount
    }

    /// この期間で「対象曜日」を絞れるか。
    var supportsWeekdaySelection: Bool { period.supportsWeekdaySelection }

    /// 指定日にこの約束が「対象」か。1日の期間なら対象曜日、週/月なら常に対象。
    /// 日付境界は `AppDay`(既定 朝4時)基準。
    func isScheduled(on day: Date = .now, calendar: Calendar = .current) -> Bool {
        guard supportsWeekdaySelection else { return true }
        if activeWeekdayValues.isEmpty { return true }
        let weekday = calendar.component(.weekday, from: AppDay.anchor(day, calendar: calendar))
        return activeWeekdayValues.contains(weekday)
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}
