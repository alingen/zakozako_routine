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

    /// 検出ワード・代替行動・検出時間帯だけをまとめて更新する(ホーム画面の詳細編集シート用)。
    func updateDetails(
        _ behavior: BlockedBehavior,
        triggerText: String,
        alternativeAction: String,
        activeStartMinute: Int?,
        activeEndMinute: Int?
    ) {
        behavior.triggerText = triggerText
        behavior.alternativeAction = alternativeAction
        behavior.activeStartMinute = activeStartMinute
        behavior.activeEndMinute = activeEndMinute
        behavior.updatedAt = .now
        save()
    }

    func setActive(_ behavior: BlockedBehavior, isActive: Bool) {
        behavior.isActive = isActive
        behavior.updatedAt = .now
        save()
    }

    func delete(_ behavior: BlockedBehavior) {
        context.delete(behavior)
        save()
    }

    /// ユーザー入力テキストにマッチする「やらないこと」を探す(簡易な部分一致 + 時間帯判定)。
    func firstMatch(for text: String, at date: Date = .now) -> BlockedBehavior? {
        guard !text.isEmpty else { return nil }
        return fetchActive().first { behavior in
            guard !behavior.triggerText.isEmpty else { return false }
            guard text.localizedCaseInsensitiveContains(behavior.triggerText) else { return false }
            return behavior.isWithinActiveWindow(at: date)
        }
    }

    private func save() {
        try? context.save()
    }
}
