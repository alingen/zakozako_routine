import Foundation
import SwiftData
import Observation

/// RoutineSessionView 専用の状態管理。
/// 実際の進行ロジックは RoutineEngine / CharacterEngine を束ねる ConversationCoordinator に委譲し、
/// ここでは「画面に出す状態(progress, messages)を async 呼び出しの結果で更新する」ことだけを担当する。
/// この境界を保っておくことで、将来ここが音声会話UIに置き換わっても Coordinator 以下は無傷で使い回せる。
@Observable
@MainActor
final class RoutineSessionViewModel {
    let routine: Routine
    private(set) var progress: RoutineProgress?
    private(set) var messages: [ConversationMessage] = []
    private(set) var characterName: String = "小悪魔コーチ"
    var inputText: String = ""

    /// 音声会話の状態。UIは既存のシンプルな画面のまま、これを見てマイクの状態だけ出す想定
    /// (見た目の作り込みは別途行う前提の、動作確認用の最小限の配線)。
    private(set) var voiceState: VoiceConversationState = .idle
    private(set) var livePartialUserText: String = ""

    private var dependencies: AppDependencies?
    private var voiceEngine: (any VoiceConversationEngine)?

    init(routine: Routine) {
        self.routine = routine
    }

    func configure(context: ModelContext) {
        guard dependencies == nil else { return }
        dependencies = AppDependencies(context: context)
        characterName = dependencies?.characterEngine.activePreset.name ?? characterName
        Task { await start() }
    }

    func start() async {
        guard let dependencies else { return }
        let turn = await dependencies.conversationCoordinator.start(routine: routine)
        progress = turn.progress
        appendCharacter(turn.characterText)
    }

    func complete() async { await record(.completed) }
    func skip() async { await record(.skipped) }
    func fail() async { await record(.failed) }

    private func record(_ outcome: StepOutcome) async {
        guard let dependencies, let progress, !progress.isFinished else { return }
        appendUser(outcome.userLabel)
        let turn = await dependencies.conversationCoordinator.recordOutcome(outcome, current: progress)
        self.progress = turn.progress
        appendCharacter(turn.characterText)
        voiceEngine?.speak(turn.characterText)
    }

    func askNextStep() async {
        guard let dependencies, let progress else { return }
        appendUser("次なに？")
        let text = await dependencies.conversationCoordinator.askNextStep(current: progress)
        appendCharacter(text)
        voiceEngine?.speak(text)
    }

    func askForHelp() async {
        guard let dependencies, let progress else { return }
        appendUser("助けて")
        let text = await dependencies.conversationCoordinator.askForHelp(current: progress)
        appendCharacter(text)
        voiceEngine?.speak(text)
    }

    func submitFreeText() async {
        guard let dependencies, let progress else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appendUser(text)
        let turn = await dependencies.conversationCoordinator.submitFreeText(text, current: progress)
        self.progress = turn.progress
        appendCharacter(turn.characterText)
    }

    func finishSession() {
        voiceEngine?.stop()
        guard let dependencies, let progress, progress.session.status == .active else { return }
        dependencies.conversationCoordinator.abandon(progress)
    }

    /// 音声会話モードを開始する。マイク/音声認識の許可が必要。
    func startVoiceMode() async {
        guard let dependencies else { return }
        if voiceEngine == nil {
            let engine = NativeVoiceConversationEngine { [weak self] text in
                guard let self, let progress = self.progress else { return "" }
                let turn = await dependencies.conversationCoordinator.submitFreeText(text, current: progress)
                self.progress = turn.progress
                return turn.characterText
            }
            engine.delegate = self
            voiceEngine = engine
        }
        do {
            try await voiceEngine?.start()
        } catch {
            appendCharacter("(音声会話を開始できなかった: \(error.localizedDescription))")
        }
    }

    func stopVoiceMode() {
        voiceEngine?.stop()
    }

    private func appendUser(_ text: String) {
        messages.append(ConversationMessage(role: .user, text: text, timestamp: .now))
    }

    private func appendCharacter(_ text: String) {
        messages.append(ConversationMessage(role: .character, text: text, timestamp: .now))
    }
}

extension RoutineSessionViewModel: VoiceConversationDelegate {
    func voiceConversation(_ engine: VoiceConversationEngine, didChangeState state: VoiceConversationState) {
        voiceState = state
        if state != .listening {
            livePartialUserText = ""
        }
    }

    func voiceConversation(_ engine: VoiceConversationEngine, didUpdatePartialUserText text: String) {
        livePartialUserText = text
    }

    func voiceConversation(_ engine: VoiceConversationEngine, didRecognizeFinalUserText text: String) {
        livePartialUserText = ""
        appendUser(text)
    }

    func voiceConversation(_ engine: VoiceConversationEngine, didReceiveCharacterText text: String) {
        appendCharacter(text)
    }
}
