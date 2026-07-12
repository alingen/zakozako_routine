import Foundation
import SwiftData

enum RoutineType: String, Codable, CaseIterable, Identifiable {
    case morning
    case night
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .morning: return "朝ルーティン"
        case .night: return "夜ルーティン"
        case .custom: return "カスタム"
        }
    }
}

@Model
final class Routine {
    @Attribute(.unique) var id: UUID
    var title: String
    var routineDescription: String
    var type: RoutineType
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    /// サボり通知を有効にするか。
    var reminderEnabled: Bool = false
    /// 通知を出す時刻(0時からの分数、0〜1439)。未設定ならnil。
    var reminderMinuteOfDay: Int?

    @Relationship(deleteRule: .cascade, inverse: \RoutineStep.routine)
    var steps: [RoutineStep] = []

    init(
        id: UUID = UUID(),
        title: String,
        routineDescription: String = "",
        type: RoutineType,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        reminderEnabled: Bool = false,
        reminderMinuteOfDay: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.routineDescription = routineDescription
        self.type = type
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.reminderEnabled = reminderEnabled
        self.reminderMinuteOfDay = reminderMinuteOfDay
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
