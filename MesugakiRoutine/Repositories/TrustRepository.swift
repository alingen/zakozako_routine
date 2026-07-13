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
    /// 実際に到達しているステージ(話題完了によるゲート済み)。
    var stage: Int { fetchOrCreate().currentStage }

    func increment(by amount: Int = 1) {
        let state = fetchOrCreate()
        state.points += amount
        state.updatedAt = .now
        try? context.save()
    }

    /// ポイントが次のステージに必要な分を満たし、かつ現ステージのフリートーク話題を
    /// 全て伝え終えていれば、次のステージに進める。両方揃わなければ何もしない。
    func tryAdvanceStage(topicProgressRepository: FreeTalkTopicProgressRepository) {
        let state = fetchOrCreate()
        let requiredPoints = state.currentStage * TrustStage.pointsPerStage
        guard state.points >= requiredPoints else { return }
        let topics = FreeTalkTopics.topics(for: state.currentStage)
        guard topicProgressRepository.allCompleted(topics) else { return }
        state.currentStage += 1
        state.updatedAt = .now
        try? context.save()
    }

    /// デバッグ・動作確認用に信頼度ポイントとステージを直接書き換える(話題完了のゲートを無視する)。
    func setPoints(_ points: Int) {
        let state = fetchOrCreate()
        state.points = points
        state.currentStage = TrustStage.stage(for: points)
        state.updatedAt = .now
        try? context.save()
    }
}
