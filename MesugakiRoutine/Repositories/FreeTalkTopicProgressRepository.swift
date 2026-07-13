import Foundation
import SwiftData

/// フリートーク話題(FreeTalkTopic)の完了状況(FreeTalkTopicProgress)の永続化を担当する。
@MainActor
final class FreeTalkTopicProgressRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    private func fetchAll() -> [FreeTalkTopicProgress] {
        let descriptor = FetchDescriptor<FreeTalkTopicProgress>()
        return (try? context.fetch(descriptor)) ?? []
    }

    func isCompleted(question: String) -> Bool {
        fetchAll().first { $0.question == question }?.isCompleted ?? false
    }

    func markCompleted(question: String) {
        if let existing = fetchAll().first(where: { $0.question == question }) {
            existing.isCompleted = true
            existing.updatedAt = .now
        } else {
            context.insert(FreeTalkTopicProgress(question: question, isCompleted: true))
        }
        try? context.save()
    }

    /// 指定した話題一覧が全て完了しているか。話題が1つも無ければ(完了すべきものが無いので)trueを返す。
    func allCompleted(_ topics: [FreeTalkTopic]) -> Bool {
        guard !topics.isEmpty else { return true }
        let completedQuestions = Set(fetchAll().filter(\.isCompleted).map(\.question))
        return topics.allSatisfy { completedQuestions.contains($0.question) }
    }
}
