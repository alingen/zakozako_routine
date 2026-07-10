import Foundation
import SwiftData

/// ユーザーが「やらないと決めた行動」。triggerText はユーザー入力とのマッチング用キーワード。
@Model
final class BlockedBehavior {
    @Attribute(.unique) var id: UUID
    var title: String
    var behaviorDescription: String
    var triggerText: String
    var counterMessage: String
    var isActive: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        behaviorDescription: String = "",
        triggerText: String = "",
        counterMessage: String = "",
        isActive: Bool = true,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.behaviorDescription = behaviorDescription
        self.triggerText = triggerText
        self.counterMessage = counterMessage
        self.isActive = isActive
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
