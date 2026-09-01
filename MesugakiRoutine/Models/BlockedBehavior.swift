import Foundation
import SwiftData

/// ユーザーが「やらないと決めた行動」。同時に挑戦中(`isActive`)にできるのは1件のみ。
///
/// 「日/週/月ごとに〇〇回まで」の回数制限を持ち、カードをタップするたびに1回消費する
/// (`usageEvents` にタイムスタンプを積む)。期間内の消費が上限以内なら、その日は「達成」として
/// 連続日数に加算される。判定は `BlockedBehaviorRepository.autoEvaluate` が日付変更時に自動で行う。
@Model
final class BlockedBehavior {
    @Attribute(.unique) var id: UUID
    var title: String
    /// 現在挑戦中かどうか。true になれるのは同時に1件のみ。
    var isActive: Bool
    /// 回数制限の集計期間(生値)。既存データの軽量マイグレーションを通すため optional String で保持する
    /// (nil は `.day` 扱い)。参照は必ず computed の `limitPeriod` を使う。
    var limitPeriodRawValue: String?
    /// 集計期間あたりの上限回数(生値)。nil は 0 扱い。参照は computed の `limitCount` を使う。
    var limitCountValue: Int?
    /// 「1回消費」した時刻のログ(生値)。nil は空配列扱い。参照は computed の `usageEvents` を使う。
    var usageEventsStore: [Date]?

    /// 回数制限の集計期間。
    var limitPeriod: HabitPeriod {
        get { limitPeriodRawValue.flatMap(HabitPeriod.init(rawValue:)) ?? .day }
        set { limitPeriodRawValue = newValue.rawValue }
    }
    /// 集計期間あたりの上限回数(設定値)。
    var limitCount: Int {
        get { limitCountValue ?? 1 }
        set { limitCountValue = newValue }
    }

    /// 実際に使う上限。1未満は1として扱う(「1回で✕」)。
    /// 期間内の消費回数がこの数に達したら、その期間は「失敗」= チェックボックスが×になる。
    var effectiveLimit: Int { max(limitCount, 1) }
    /// 「1回消費」した時刻のログ。期間内の件数が `limitCount` を超えたらその日は未達成扱い。
    var usageEvents: [Date] {
        get { usageEventsStore ?? [] }
        set { usageEventsStore = newValue }
    }
    /// 連続で「達成」している日数。上限超過の日があると0にリセットされる。
    /// `BlockedBehaviorRepository.autoEvaluate` が日付変更時に自動更新する。
    var currentStreakDays: Int = 0
    /// 自動判定(autoEvaluate)で最後に評価済みの日。この翌日から未評価。
    var lastCheckInDate: Date?
    /// 14日間守り切って「卒業」した日時。nilならまだ挑戦中。
    var masteredAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        isActive: Bool = true,
        limitPeriod: HabitPeriod = .day,
        limitCount: Int = 1,
        usageEvents: [Date] = [],
        currentStreakDays: Int = 0,
        lastCheckInDate: Date? = nil,
        masteredAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.isActive = isActive
        self.limitPeriodRawValue = limitPeriod.rawValue
        self.limitCountValue = limitCount
        self.usageEventsStore = usageEvents
        self.currentStreakDays = currentStreakDays
        self.lastCheckInDate = lastCheckInDate
        self.masteredAt = masteredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 14日間の達成に必要な連続日数。
    static let masteryStreakDays = 14

    /// 指定日を含む集計期間ウィンドウ [start, end)。
    func limitWindow(containing day: Date, calendar: Calendar = .current) -> DateInterval {
        limitPeriod.window(containing: day, calendar: calendar)
    }

    /// 指定日の終了時点で、その日を含む期間の消費回数が上限に達しているか(達したら「失敗」)。
    func exceededLimit(on day: Date, calendar: Calendar = .current) -> Bool {
        let window = limitWindow(containing: day, calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? window.end
        let upperBound = min(window.end, dayEnd)
        let count = usageEvents.filter { $0 >= window.start && $0 < upperBound }.count
        return count >= effectiveLimit
    }

    /// 現在時刻を含む期間の、これまでの消費回数。
    func usageInCurrentPeriod(now: Date = .now, calendar: Calendar = .current) -> Int {
        let window = limitWindow(containing: now, calendar: calendar)
        return usageEvents.filter { $0 >= window.start && $0 <= now }.count
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}
