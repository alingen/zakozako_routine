import Foundation

/// キャラクターが反応すべき状況。RoutineEngine / ConversationCoordinator から渡される。
enum CharacterSituation {
    case routineStarted(stepName: String)
    case stepCompleted(nextStepName: String?)
    case stepSkipped(nextStepName: String?)
    case stepFailed(nextStepName: String?)
    case routineCompleted
    case helpRequested(currentStepName: String)
    case blockedBehaviorDetected(behaviorTitle: String, counterMessage: String)
    case nextStepQuery(currentStepName: String?)
    /// 自由入力テキスト。ChatGPT等に差し替えた際は、これがそのままユーザー発言として渡る。
    case freeText(String)
}

/// AI視点での発言者。会話履歴をAPIに渡す際の role にマッピングする。
enum ChatRole {
    case user
    case assistant
}

/// 会話履歴の1ターン分。ConversationCoordinator がセッション中ずっと蓄積し、
/// AI応答生成のたびに「これまでの流れ」として渡す。
struct ConversationHistoryItem {
    let role: ChatRole
    let text: String
}

/// AI応答生成に渡す文脈。将来 OpenAI Realtime API 等に差し替える際も同じ形で渡せるようにする。
struct CharacterResponseContext {
    let situation: CharacterSituation
    let preset: CharacterPreset
    let recentUserText: String?
    /// 直近までの会話履歴(今回のsituationは含まない)。ChatGPTのようなAPIに文脈を持たせるために使う。
    var history: [ConversationHistoryItem] = []
}

/// AI応答の結果。将来は音声合成用のメタデータ（SSML等）をここに足せるようにしておく。
struct CharacterResponse {
    let text: String
}

/// キャラクターの応答生成を抽象化するプロトコル。
///
/// 現在は `LocalCharacterResponseGenerator`(ローカルテンプレート) と
/// `OpenAICharacterResponseGenerator`(OpenAI Chat Completions API) の2実装がある。
/// どちらを使うかは `AppDependencies` で切り替えるだけで、CharacterEngine 以降のコードは変更不要。
protocol CharacterResponseGenerating {
    func generateResponse(context: CharacterResponseContext) async -> CharacterResponse
}
