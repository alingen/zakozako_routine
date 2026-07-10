import Foundation

/// 常時接続の音声会話セッションが取りうる状態。
/// Realtime API のような双方向ストリーミングでも、Apple標準音声によるターン制の疑似会話でも、
/// UI側はこの状態だけを見ていればよいように設計している。
enum VoiceConversationState: Equatable {
    case idle
    case listening
    case thinking
    case speaking
    case error(String)
}

/// 音声会話セッションから発生するイベントの通知先。
@MainActor
protocol VoiceConversationDelegate: AnyObject {
    func voiceConversation(_ engine: VoiceConversationEngine, didChangeState state: VoiceConversationState)
    func voiceConversation(_ engine: VoiceConversationEngine, didUpdatePartialUserText text: String)
    func voiceConversation(_ engine: VoiceConversationEngine, didRecognizeFinalUserText text: String)
    func voiceConversation(_ engine: VoiceConversationEngine, didReceiveCharacterText text: String)
}

/// 「キャラクターとの常時接続音声会話」を抽象化するプロトコル。
///
/// `CharacterResponseGenerating` が1問1答のテキスト応答を抽象化しているのに対し、
/// こちらは「聞く→考える→話す」を繰り返す持続的なセッションのライフサイクルを抽象化する。
///
/// 現在は `NativeVoiceConversationEngine`(Apple標準のSFSpeechRecognizer + AVSpeechSynthesizer)が
/// 唯一の実装。将来 `OpenAIRealtimeVoiceConversationEngine`(OpenAI Realtime API / GPT-Live)に
/// 差し替えても、呼び出し側(ViewModel)のコードは変更不要になるよう、状態遷移とイベントの形を
/// 共通化している。
@MainActor
protocol VoiceConversationEngine: AnyObject {
    var delegate: VoiceConversationDelegate? { get set }
    var state: VoiceConversationState { get }

    /// 音声会話セッションを開始する(マイク・音声認識の使用許可の要求を含む)。
    func start() async throws

    /// セッションを終了する。
    func stop()

    /// ユーザーの発話がきっかけではない状況(ボタン操作などによるキャラクターの返答)を読み上げる。
    func speak(_ text: String)
}
