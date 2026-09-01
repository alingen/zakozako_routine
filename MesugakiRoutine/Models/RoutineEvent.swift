import Foundation
import SwiftData

enum RoutineEventType: String, Codable {
    case started
    case completedStep = "completed_step"
    case skippedStep = "skipped_step"
    case failedStep = "failed_step"
    case completedRoutine = "completed_routine"
    case abandoned
}

/// ルーティン実行中の1イベント(開始・ステップ完了・完了など)。実行履歴・進捗計算の元データ。
@Model
final class RoutineEvent {
    @Attribute(.unique) var id: UUID
    var stepId: UUID?
    var eventType: RoutineEventType
    var createdAt: Date

    var session: RoutineSession?

    init(
        id: UUID = UUID(),
        stepId: UUID? = nil,
        eventType: RoutineEventType,
        createdAt: Date = .now,
        session: RoutineSession? = nil
    ) {
        self.id = id
        self.stepId = stepId
        self.eventType = eventType
        self.createdAt = createdAt
        self.session = session
    }
}
