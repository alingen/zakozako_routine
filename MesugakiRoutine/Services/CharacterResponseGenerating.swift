import Foundation

/// キャラクターが反応すべき状況。RoutineEngine / ConversationCoordinator から渡される。
enum CharacterSituation {
    /// routineTitle は今開始したルーティン名、stepName は最初のステップ名。
    /// (朝/夜の区別は廃止。挨拶は時間帯ではなくルーティンの進み具合で出し分ける)
    case routineStarted(routineTitle: String, stepName: String)
    case stepCompleted(nextStepName: String?)
    case stepSkipped(nextStepName: String?)
    case stepFailed(nextStepName: String?)
    /// routineTitle は完了したルーティン名、allRoutinesCompletedToday は
    /// 「この完了で、今日やる予定のルーティンが全部終わったか」。
    case routineCompleted(routineTitle: String, allRoutinesCompletedToday: Bool)
    case helpRequested(currentStepName: String)
    /// reason はその行動をやめると決めた理由(例: 「仕事をさぼらないため」)、alternativeAction は
    /// 代わりに勧める具体的な行動(例: 「音楽をかける」)。どちらも空文字なら特に触れない。
    case blockedBehaviorDetected(behaviorTitle: String, counterMessage: String, reason: String, alternativeAction: String)
    /// ホーム画面を開いた時の一言。streakDays は継続日数(初回でも1)、hasPendingRoutineToday は
    /// 「今日やる予定のルーティンがまだ残っている(急かしてよい)」かどうか。
    case homeGreeting(streakDays: Int, hasPendingRoutineToday: Bool)
    /// 自由入力テキスト。ChatGPT等に差し替えた際は、これがそのままユーザー発言として渡る。
    case freeText(String)
    /// ルーティン完了後、「少し話す」でフリートークに入った直後。キャラクター側から話題を振る。
    /// topicはConversationCoordinatorが信頼度ステージに応じて選んだ話題(nilなら全て話し終えている)。
    case freeTalkStarted(topic: FreeTalkTopic?)
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
    /// キャラクターがユーザーを呼ぶ時の呼び名。空文字なら特に呼びかけない(AppSettingsStore.userNicknameで設定)。
    let userNickname: String
    /// 現在の信頼度ステージ(TrustStage.stage(for:)で算出)。低いほど警戒心が強い状態を表す。
    let trustStage: Int
    /// これまでの会話でわかっているユーザーの情報(key: value)。将来の会話に自然に組み込む材料として使う。
    let userProfileFacts: [String: String]
    /// 直前にキャラクターから振った話題(FreeTalkTopic)のうち、まだ伝え終えていない「伝えたい情報」。
    /// フリートーク中の会話で、これを実際に伝えられたかどうかの判定に使う(GPT応答からのみ利用)。
    let pendingDisclosure: String?
    /// 直近までの会話履歴(今回のsituationは含まない)。ChatGPTのようなAPIに文脈を持たせるために使う。
    var history: [ConversationHistoryItem] = []
}

/// AI応答の結果。将来は音声合成用のメタデータ（SSML等）をここに足せるようにしておく。
struct CharacterResponse {
    let text: String
    /// 応答の中でユーザーが新たに明かした情報(key: value)。GPT応答からのみ抽出される(Localは常に空)。
    var extractedFacts: [String: String] = [:]
    /// `pendingDisclosure`を今回の応答で実際に伝え終えたか。GPT応答からのみ判定される(Localは常にfalse)。
    var disclosureCompleted: Bool = false
}

/// キャラクターの応答生成を抽象化するプロトコル。
///
/// 現在は `LocalCharacterResponseGenerator`(ローカルテンプレート) と
/// `OpenAICharacterResponseGenerator`(OpenAI Chat Completions API) の2実装がある。
/// どちらを使うかは `AppDependencies` で切り替えるだけで、CharacterEngine 以降のコードは変更不要。
protocol CharacterResponseGenerating {
    func generateResponse(context: CharacterResponseContext) async -> CharacterResponse
}
