import Foundation
import SwiftData

/// 「やらないこと」リストの永続化を担当する。
@MainActor
final class BlockedBehaviorRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() -> [BlockedBehavior] {
        let descriptor = FetchDescriptor<BlockedBehavior>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    func fetchActive() -> [BlockedBehavior] {
        fetchAll().filter(\.isActive)
    }

    @discardableResult
    func create(title: String, description: String, triggerText: String, counterMessage: String) -> BlockedBehavior {
        let behavior = BlockedBehavior(
            title: title,
            behaviorDescription: description,
            triggerText: triggerText,
            counterMessage: counterMessage
        )
        context.insert(behavior)
        save()
        return behavior
    }

    func update(_ behavior: BlockedBehavior, title: String, description: String, triggerText: String, counterMessage: String, isActive: Bool) {
        behavior.title = title
        behavior.behaviorDescription = description
        behavior.triggerText = triggerText
        behavior.counterMessage = counterMessage
        behavior.isActive = isActive
        behavior.updatedAt = .now
        save()
    }

    func delete(_ behavior: BlockedBehavior) {
        context.delete(behavior)
        save()
    }

    /// ユーザー入力テキストにマッチする「やらないこと」を探す（簡易な部分一致）。
    func firstMatch(for text: String) -> BlockedBehavior? {
        guard !text.isEmpty else { return nil }
        return fetchActive().first { behavior in
            !behavior.triggerText.isEmpty && text.localizedCaseInsensitiveContains(behavior.triggerText)
        }
    }

    private func save() {
        try? context.save()
    }
}
