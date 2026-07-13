import Foundation
import SwiftData

/// キャラクターとの信頼度。アプリ全体で1レコードだけ持つ想定(TrustRepositoryが1件のみ保証する)。
/// ルーティン完了・自由会話のたびにポイントが加算されるが、実際にステージが上がるのは
/// ポイントが足り、かつそのステージのフリートーク話題(FreeTalkTopics)を全て伝え終えた時だけ
/// (TrustRepository.tryAdvanceStageが判定する)。
@Model
final class TrustState {
    @Attribute(.unique) var id: UUID
    var points: Int
    /// 実際に到達しているステージ(話題完了によるゲート済み)。ポイントだけのTrustStage.stage(for:)とは異なる。
    var currentStage: Int = 1
    var updatedAt: Date

    init(id: UUID = UUID(), points: Int = 0, currentStage: Int = 1, updatedAt: Date = .now) {
        self.id = id
        self.points = points
        self.currentStage = currentStage
        self.updatedAt = updatedAt
    }
}

/// 信頼度ポイントの目安ステージを導出する。5ポイントごとに1ステージ分、上限なしの単純な計算。
/// 実際の到達ステージ(TrustState.currentStage)は、これに加えて話題完了のゲートがかかる。
enum TrustStage {
    static let pointsPerStage = 5

    static func stage(for points: Int) -> Int {
        max(1, points / pointsPerStage + 1)
    }
}
