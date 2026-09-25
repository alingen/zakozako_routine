import Foundation
import SwiftData

/// 多数の状況フラグを持たず、操作の発生時刻をSwiftDataに保存する。
@MainActor
final class UserActionEventRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func record(
        _ type: UserActionEventType,
        occurredAt: Date = .now
    ) throws -> UserActionEvent {
        let event = UserActionEvent(eventType: type, occurredAt: occurredAt)
        do {
            try context.transaction {
                context.insert(event)
                try context.save()
            }
            return event
        } catch {
            context.rollback()
            throw error
        }
    }

    func fetchAll() throws -> [UserActionEvent] {
        try context.fetch(FetchDescriptor<UserActionEvent>(
            sortBy: [SortDescriptor(\.occurredAt, order: .forward)]
        ))
    }
}
