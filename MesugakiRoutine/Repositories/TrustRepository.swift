import Foundation
import SwiftData

/// キャラクターとの信頼度(TrustState)の永続化を担当する。常に1レコードのみ存在する前提で、
/// 無ければ取得時に作成する。
@MainActor
final class TrustRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func fetchOrCreate() -> TrustState {
        let descriptor = FetchDescriptor<TrustState>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = TrustState()
        context.insert(created)
        try? context.save()
        return created
    }

    var points: Int { fetchOrCreate().points }
    var stage: Int { TrustStage.stage(for: points) }

    func increment(by amount: Int = 1) {
        let state = fetchOrCreate()
        state.points += amount
        state.updatedAt = .now
        try? context.save()
    }

    /// デバッグ・動作確認用に信頼度ポイントを直接書き換える。
    func setPoints(_ points: Int) {
        let state = fetchOrCreate()
        state.points = points
        state.updatedAt = .now
        try? context.save()
    }
}
