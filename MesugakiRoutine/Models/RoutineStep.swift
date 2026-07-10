import Foundation
import SwiftData

@Model
final class RoutineStep {
    @Attribute(.unique) var id: UUID
    var title: String
    var stepDescription: String
    var orderIndex: Int
    var estimatedMinutes: Int
    var isRequired: Bool
    var createdAt: Date
    var updatedAt: Date

    var routine: Routine?

    init(
        id: UUID = UUID(),
        title: String,
        stepDescription: String = "",
        orderIndex: Int,
        estimatedMinutes: Int = 1,
        isRequired: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        routine: Routine? = nil
    ) {
        self.id = id
        self.title = title
        self.stepDescription = stepDescription
        self.orderIndex = orderIndex
        self.estimatedMinutes = estimatedMinutes
        self.isRequired = isRequired
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.routine = routine
    }
}
