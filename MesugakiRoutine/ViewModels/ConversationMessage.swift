import Foundation

/// RoutineSessionView に表示する会話ログの1行。テキストUI専用の表示用モデルで、永続化はしない
/// (永続化された履歴は RoutineEvent 側が担う)。
struct ConversationMessage: Identifiable {
    enum Role {
        case user
        case character
    }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date
}
