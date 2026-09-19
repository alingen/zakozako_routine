import Foundation
import SwiftData

enum BlockedBehaviorTrackingKind: String, Codable {
    case manual
    case screenTime
}

/// ユーザーが「やらないと決めた行動」。同時に挑戦中(`isActive`)にできるのは1件のみ。
///
/// 「日/週/月ごとに〇〇回まで」の回数制限を持ち、ユーザーが敗北を確定すると
/// `usageEvents` に1回分が記録される。期間内の消費が上限未満なら、その日は「達成」として
/// 連続日数に加算される。判定は `BlockedBehaviorRepository.autoEvaluate` が日付変更時に自動で行う。
@Model
final class BlockedBehavior {
    @Attribute(.unique) var id: UUID
    var title: String
    /// カードの円の中に表示する SF Symbol 名。既存データは nil のまま扱える。
    var iconName: String?
    /// 現在挑戦中かどうか。true になれるのは同時に1件のみ。
    var isActive: Bool
    /// 回数制限の集計期間(生値)。既存データの軽量マイグレーションを通すため optional String で保持する
    /// (nil は `.day` 扱い)。参照は必ず computed の `limitPeriod` を使う。
    var limitPeriodRawValue: String?
    /// 集計期間あたりの上限回数(生値)。nil は 0 扱い。参照は computed の `limitCount` を使う。
    var limitCountValue: Int?
    /// 失敗判定用の時刻ログ(生値)。nil は空配列扱い。参照は computed の `usageEvents` を使う。
    var usageEventsStore: [Date]?
    /// 判定方法(生値)。既存データは nil のため、computed の `trackingKind` で手動判定として扱う。
    var trackingKindRawValue: String?
    /// Screen Time の上限分数(生値)。既存データの互換性を保つため optional で保持する。
    var screenTimeLimitMinutesValue: Int?
    /// FamilyControls で選択したアプリ・カテゴリ等をエンコードしたデータ。
    var screenTimeSelectionData: Data?
    /// Device Activity 拡張が1日の監視完了を確認した日。未監視日はここに入らず、達成にも数えない。
    /// 既存データを軽量マイグレーションできるよう optional で保持する。
    var screenTimeVerifiedDaysStore: [Date]?
    /// 上限超過が属する監視intervalの開始日時。タイムゾーン変更後も元の日付を保持する。
    var screenTimeFailedDaysStore: [Date]?

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

    /// 実際に使う上限。1未満は1として扱う(「1回で失敗」)。
    /// 期間内の消費回数がこの数に達したら、その期間は「失敗」になる。
    var effectiveLimit: Int { max(limitCount, 1) }
    /// 失敗判定用の時刻ログ。期間内の件数が `effectiveLimit` に達したらその日は未達成扱い。
    var usageEvents: [Date] {
        get { usageEventsStore ?? [] }
        set { usageEventsStore = newValue }
    }
    /// 失敗をユーザー操作で記録するか、Screen Time の上限到達で記録するか。
    var trackingKind: BlockedBehaviorTrackingKind {
        get {
            trackingKindRawValue.flatMap(BlockedBehaviorTrackingKind.init(rawValue:)) ?? .manual
        }
        set {
            trackingKindRawValue = newValue.rawValue
        }
    }
    /// Screen Time の上限分数。未設定は20分、範囲外の値は1分〜24時間に収める。
    var screenTimeLimitMinutes: Int {
        get { min(max(screenTimeLimitMinutesValue ?? 20, 1), 1_440) }
        set { screenTimeLimitMinutesValue = min(max(newValue, 1), 1_440) }
    }
    var screenTimeVerifiedDays: [Date] {
        get { screenTimeVerifiedDaysStore ?? [] }
        set { screenTimeVerifiedDaysStore = newValue }
    }
    var screenTimeFailedDays: [Date] {
        get { screenTimeFailedDaysStore ?? [] }
        set { screenTimeFailedDaysStore = newValue }
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
        iconName: String? = nil,
        isActive: Bool = true,
        limitPeriod: HabitPeriod = .day,
        limitCount: Int = 1,
        usageEvents: [Date] = [],
        trackingKind: BlockedBehaviorTrackingKind = .manual,
        screenTimeLimitMinutes: Int? = nil,
        screenTimeSelectionData: Data? = nil,
        screenTimeVerifiedDays: [Date] = [],
        screenTimeFailedDays: [Date] = [],
        currentStreakDays: Int = 0,
        lastCheckInDate: Date? = nil,
        masteredAt: Date? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.isActive = isActive
        self.limitPeriodRawValue = limitPeriod.rawValue
        self.limitCountValue = limitCount
        self.usageEventsStore = usageEvents
        self.trackingKindRawValue = trackingKind.rawValue
        self.screenTimeLimitMinutesValue = screenTimeLimitMinutes.map {
            min(max($0, 1), 1_440)
        }
        self.screenTimeSelectionData = screenTimeSelectionData
        self.screenTimeVerifiedDaysStore = screenTimeVerifiedDays
        self.screenTimeFailedDaysStore = screenTimeFailedDays
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
        let dayStart = AppDay.startOfDay(for: day, calendar: calendar)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? window.end
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
