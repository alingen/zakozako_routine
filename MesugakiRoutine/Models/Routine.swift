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

    @Relationship(deleteRule: .cascade, inverse: \RoutineStep.routine)
    var steps: [RoutineStep] = []

    init(
        id: UUID = UUID(),
        title: String,
        routineDescription: String = "",
        type: RoutineType,
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.routineDescription = routineDescription
        self.type = type
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var orderedSteps: [RoutineStep] {
        steps.sorted { $0.orderIndex < $1.orderIndex }
    }
}
