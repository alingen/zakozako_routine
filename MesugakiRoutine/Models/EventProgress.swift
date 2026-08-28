import Foundation
import SwiftData

/// イベントごとの解放/完了の状態。条件を満たすと `unlockedAt` が入り(=解放)、
/// ユーザーが実際に見て最後まで再生すると `completedAt` が入る(=完了)。
///
/// 「解放」は強制開始ではない。解放済み・未完了のイベントは、今日の会話の後やホーム画面から
/// ユーザーが任意のタイミングで開始できる。「あとにする」を選んでも状態は変わらない(消えない)。
@Model
final class EventProgress {
    @Attribute(.unique) var eventId: String
    var unlockedAt: Date?
    var completedAt: Date?
    /// 「あとにする」を最後に押した日時(任意・表示用)。
    var deferredAt: Date?
    var updatedAt: Date

    init(
        eventId: String,
        unlockedAt: Date? = nil,
        completedAt: Date? = nil,
        deferredAt: Date? = nil,
        updatedAt: Date = .now
    ) {
        self.eventId = eventId
        self.unlockedAt = unlockedAt
        self.completedAt = completedAt
        self.deferredAt = deferredAt
        self.updatedAt = updatedAt
    }

    var isUnlocked: Bool { unlockedAt != nil }
    var isCompleted: Bool { completedAt != nil }
}
