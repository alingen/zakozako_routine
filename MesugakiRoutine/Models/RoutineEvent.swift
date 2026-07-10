import Foundation
import SwiftData

enum RoutineEventType: String, Codable {
    case started
    case completedStep = "completed_step"
    case skippedStep = "skipped_step"
    case failedStep = "failed_step"
    case blockedBehavior = "blocked_behavior"
    case completedRoutine = "completed_routine"
    case abandoned
}

@Model
final class RoutineEvent {
    @Attribute(.unique) var id: UUID
    var stepId: UUID?
    var eventType: RoutineEventType
    var userText: String?
    var aiText: String?
    var createdAt: Date

    var session: RoutineSession?

    init(
        id: UUID = UUID(),
        stepId: UUID? = nil,
        eventType: RoutineEventType,
        userText: String? = nil,
        aiText: String? = nil,
        createdAt: Date = .now,
        session: RoutineSession? = nil
    ) {
        self.id = id
        self.stepId = stepId
        self.eventType = eventType
        self.userText = userText
        self.aiText = aiText
        self.createdAt = createdAt
        self.session = session
    }
}
