import Foundation
import SwiftData

/// フリートークの話題(FreeTalkTopic)ごとの完了状況。`question`をキーに、伝えたい情報(disclosure)を
/// 実際に会話で伝え終えたら`isCompleted`をtrueにする。
@Model
final class FreeTalkTopicProgress {
    @Attribute(.unique) var question: String
    var isCompleted: Bool
    var updatedAt: Date

    init(question: String, isCompleted: Bool = false, updatedAt: Date = .now) {
        self.question = question
        self.isCompleted = isCompleted
        self.updatedAt = updatedAt
    }
}
