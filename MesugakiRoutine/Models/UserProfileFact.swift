import Foundation
import SwiftData

/// 自由会話の中でユーザーが明かした情報をkey-value形式で保存しておく(例: key="住み", value="大田区")。
/// 将来の会話でキャラクターが自然に触れるための材料として使う。
@Model
final class UserProfileFact {
    @Attribute(.unique) var key: String
    var value: String
    var updatedAt: Date

    init(key: String, value: String, updatedAt: Date = .now) {
        self.key = key
        self.value = value
        self.updatedAt = updatedAt
    }
}
