import Foundation
import SwiftData

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    /// 開始予定時刻(0時からの分数、0〜1439)。未設定ならnil。
    /// サボり通知は、有効な全ルーティンに対して共通の設定(AppSettingsStore)で
    /// 「この時刻から何分後」を計算するために使う。ルーティンごとの個別設定は持たない。
    var scheduledStartMinute: Int?

    /// 対象曜日(Weekdayのraw value)。デフォルトは全曜日。
    var activeWeekdayValues: [Int] = Weekday.allWeekdayValues

    @Relationship(deleteRule: .cascade, inverse: \RoutineStep.routine)
    var steps: [RoutineStep] = []

    init(
        id: UUID = UUID(),
        title: String,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        scheduledStartMinute: Int? = nil,
        activeWeekdayValues: [Int] = Weekday.allWeekdayValues
    ) {
        self.id = id
        self.title = title
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.scheduledStartMinute = scheduledStartMinute
        self.activeWeekdayValues = activeWeekdayValues
    }

    var orderedSteps: [RoutineStep] {
        steps.sorted { $0.orderIndex < $1.orderIndex }
    }

    static func minutes(from date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func date(fromMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
    }
}
