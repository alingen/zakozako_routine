import Foundation
import SwiftData

enum RoutineSessionStatus: String, Codable {
    case active
    case completed
    case abandoned
}

@Model
final class RoutineSession {
    @Attribute(.unique) var id: UUID
    var routineId: UUID
    var startedAt: Date
    var completedAt: Date?
    var status: RoutineSessionStatus
    var currentStepId: UUID?

    @Relationship(deleteRule: .cascade, inverse: \RoutineEvent.session)
    var events: [RoutineEvent] = []

    init(
        id: UUID = UUID(),
        routineId: UUID,
        startedAt: Date = .now,
        completedAt: Date? = nil,
        status: RoutineSessionStatus = .active,
        currentStepId: UUID? = nil
    ) {
        self.id = id
        self.routineId = routineId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.status = status
        self.currentStepId = currentStepId
    }
}
