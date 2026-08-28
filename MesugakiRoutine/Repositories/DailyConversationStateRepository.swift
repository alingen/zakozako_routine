import Foundation
import SwiftData

/// 「今日の会話」の進行状況(DailyConversationState)の永続化を担当する。
/// 常に1レコードのみ存在する前提で、無ければ取得時に作成する(TrustRepositoryと同じ方針)。
@MainActor
final class DailyConversationStateRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func fetchOrCreate() -> DailyConversationState {
        let descriptor = FetchDescriptor<DailyConversationState>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = DailyConversationState()
        context.insert(created)
        try? context.save()
        return created
    }

    /// 次に再生すべき会話のインデックス(0始まり)。
    var currentIndex: Int { fetchOrCreate().currentIndex }

    /// 会話を最後まで完了した時に呼ぶ。次の会話へ進める。
    /// (途中で閉じた場合は呼ばない = 見逃さず、同じ会話を次回続きから再生する)
    func advance() {
        let state = fetchOrCreate()
        state.currentIndex += 1
        state.lastCompletedAt = .now
        state.updatedAt = .now
        try? context.save()
    }

    /// デバッグ・動作確認用にインデックスを直接指定する。
    func setIndex(_ index: Int) {
        let state = fetchOrCreate()
        state.currentIndex = max(0, index)
        state.updatedAt = .now
        try? context.save()
    }
}
