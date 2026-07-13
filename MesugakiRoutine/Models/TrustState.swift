import Foundation
import SwiftData

/// キャラクターとの信頼度。アプリ全体で1レコードだけ持つ想定(TrustRepositoryが1件のみ保証する)。
/// ルーティン完了・自由会話のたびにポイントが加算され、一定ポイントごとにステージが上がる。
/// ステージに応じて応答内容を変える処理は未実装(将来ここを参照して分岐させる想定)。
@Model
final class TrustState {
    @Attribute(.unique) var id: UUID
    var points: Int
    var updatedAt: Date

    init(id: UUID = UUID(), points: Int = 0, updatedAt: Date = .now) {
        self.id = id
        self.points = points
        self.updatedAt = updatedAt
    }
}

/// 信頼度ポイントからステージを導出する。5ポイントごとに1ステージ上がる、上限なしの単純な計算。
enum TrustStage {
    static let pointsPerStage = 5

    static func stage(for points: Int) -> Int {
        max(1, points / pointsPerStage + 1)
    }
}
