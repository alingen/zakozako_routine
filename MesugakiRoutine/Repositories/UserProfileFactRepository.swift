import Foundation
import SwiftData

/// 自由会話から抽出したユーザー情報(UserProfileFact)の永続化を担当する。
@MainActor
final class UserProfileFactRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func fetchAll() -> [UserProfileFact] {
        let descriptor = FetchDescriptor<UserProfileFact>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// キャラクターの応答生成に渡す用の辞書表現。
    var allFacts: [String: String] {
        Dictionary(uniqueKeysWithValues: fetchAll().map { ($0.key, $0.value) })
    }

    /// key が既存なら値を更新し、無ければ新規作成する。
    func upsert(key: String, value: String) {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty, !trimmedValue.isEmpty else { return }

        let descriptor = FetchDescriptor<UserProfileFact>()
        let existing = (try? context.fetch(descriptor))?.first { $0.key == trimmedKey }
        if let existing {
            existing.value = trimmedValue
            existing.updatedAt = .now
        } else {
            context.insert(UserProfileFact(key: trimmedKey, value: trimmedValue))
        }
        try? context.save()
    }

    func delete(_ fact: UserProfileFact) {
        context.delete(fact)
        try? context.save()
    }
}
