import Foundation
import SwiftData

/// 関係性フェーズ(RelationshipState)の永続化を担当する。常に1レコードのみ存在する前提で、
/// 無ければ取得時に作成する(TrustRepositoryと同じ方針)。
@MainActor
final class RelationshipRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    @discardableResult
    func fetchOrCreate() -> RelationshipState {
        let descriptor = FetchDescriptor<RelationshipState>()
        if let existing = (try? context.fetch(descriptor))?.first {
            return existing
        }
        let created = RelationshipState()
        context.insert(created)
        try? context.save()
        return created
    }

    var phase: Int { fetchOrCreate().phase }

    /// 指定フェーズまで進める(現在より低い値が渡された場合は何もしない=後退しない)。
    func advance(toPhase target: Int) {
        let state = fetchOrCreate()
        let clamped = min(max(target, 0), RelationshipState.maxPhase)
        guard clamped > state.phase else { return }
        state.phase = clamped
        state.updatedAt = .now
        try? context.save()
    }

    /// デバッグ用にフェーズを直接指定する。
    func setPhase(_ phase: Int) {
        let state = fetchOrCreate()
        state.phase = min(max(phase, 0), RelationshipState.maxPhase)
        state.updatedAt = .now
        try? context.save()
    }
}
