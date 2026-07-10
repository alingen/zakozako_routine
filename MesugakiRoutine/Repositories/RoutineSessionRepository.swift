import Foundation
import SwiftData

/// RoutineSession / RoutineEvent の永続化を担当する。
@MainActor
final class RoutineSessionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAllSessions() -> [RoutineSession] {
        let descriptor = FetchDescriptor<RoutineSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchActiveSession(routineId: UUID) -> RoutineSession? {
        fetchAllSessions().first { $0.routineId == routineId && $0.status == .active }
    }

    @discardableResult
    func createSession(routineId: UUID, currentStepId: UUID?) -> RoutineSession {
        let session = RoutineSession(routineId: routineId, currentStepId: currentStepId)
        context.insert(session)
        save()
        return session
    }

    func updateStatus(_ session: RoutineSession, status: RoutineSessionStatus, completedAt: Date? = nil) {
        session.status = status
        session.completedAt = completedAt
        save()
    }

    func updateCurrentStep(_ session: RoutineSession, stepId: UUID?) {
        session.currentStepId = stepId
        save()
    }

    @discardableResult
    func appendEvent(
        to session: RoutineSession,
        stepId: UUID?,
        eventType: RoutineEventType,
        userText: String? = nil,
        aiText: String? = nil
    ) -> RoutineEvent {
        let event = RoutineEvent(
            stepId: stepId,
            eventType: eventType,
            userText: userText,
            aiText: aiText,
            session: session
        )
        context.insert(event)
        save()
        return event
    }

    /// 完了系イベントを直近から取得する（Home画面の「最近の完了ログ」用）。
    func fetchRecentEvents(limit: Int = 10) -> [RoutineEvent] {
        let descriptor = FetchDescriptor<RoutineEvent>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return Array(all.prefix(limit))
    }

    private func save() {
        try? context.save()
    }
}
