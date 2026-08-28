import Foundation
import SwiftData

/// 「今日の会話」の進行状況。アプリ全体で1レコードのみ持つ(DailyConversationStateRepositoryが担保)。
///
/// カレンダー日付ではなく「ユーザーが消化した会話数」で管理する。アプリを開かなかった日があっても
/// 次に会話した時に続きから進むため、会話を見逃すことはない。
@Model
final class DailyConversationState {
    @Attribute(.unique) var id: UUID
    /// 次に再生する会話のインデックス(0始まり)。会話を最後まで完了するたびに +1 される。
    var currentIndex: Int
    /// 直近で会話を完了した日時。
    var lastCompletedAt: Date?
    var updatedAt: Date

    init(id: UUID = UUID(), currentIndex: Int = 0, lastCompletedAt: Date? = nil, updatedAt: Date = .now) {
        self.id = id
        self.currentIndex = currentIndex
        self.lastCompletedAt = lastCompletedAt
        self.updatedAt = updatedAt
    }
}
