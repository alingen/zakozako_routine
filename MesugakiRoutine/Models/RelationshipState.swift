import Foundation
import SwiftData

/// キャラクターとの関係性フェーズ。アプリ全体で1レコードのみ(RelationshipRepositoryが担保)。
///
/// 信頼度(TrustState)が習慣の積み重ねで増える数値なのに対し、こちらは「関係性の段階」を表す。
/// 今日の会話では進展させず、大イベントの完了によってのみ前進する(STEP 7の役割整理)。
///
/// - phase 0: まだそれほど親しくない
/// - phase 1: 多少信用している
/// - phase 2: かなり親しい
@Model
final class RelationshipState {
    @Attribute(.unique) var id: UUID
    var phase: Int
    var updatedAt: Date

    init(id: UUID = UUID(), phase: Int = 0, updatedAt: Date = .now) {
        self.id = id
        self.phase = phase
        self.updatedAt = updatedAt
    }

    static let maxPhase = 2
}
