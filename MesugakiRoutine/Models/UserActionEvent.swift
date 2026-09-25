import Foundation
import SwiftData

/// リアクション条件に使う、ユーザー操作とアプリ来訪の事実。
/// 約束の達成や「やらないこと」の日別結果は既存モデルが正本なので、ここへ複製しない。
enum UserActionEventType: String {
    case prohibitionUrge = "prohibition_urge"
    case prohibitionFailed = "prohibition_failed"
    case interactionScreenOpened = "interaction_screen_opened"
    case characterTapped = "character_tapped"
    case appOpened = "app_opened"
}

enum UserActionTargetType: String {
    case prohibition
}

@Model
final class UserActionEvent {
    @Attribute(.unique) var id: UUID
    var eventTypeRawValue: String
    var targetTypeRawValue: String?
    var targetID: UUID?
    var occurredAt: Date

    var eventType: UserActionEventType? { UserActionEventType(rawValue: eventTypeRawValue) }
    var targetType: UserActionTargetType? {
        targetTypeRawValue.flatMap(UserActionTargetType.init(rawValue:))
    }

    init(
        id: UUID = UUID(),
        eventType: UserActionEventType,
        targetType: UserActionTargetType? = nil,
        targetID: UUID? = nil,
        occurredAt: Date = .now
    ) {
        self.id = id
        self.eventTypeRawValue = eventType.rawValue
        self.targetTypeRawValue = targetType?.rawValue
        self.targetID = targetID
        self.occurredAt = occurredAt
    }
}
