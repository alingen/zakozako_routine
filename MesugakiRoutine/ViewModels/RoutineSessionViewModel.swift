import Foundation
import SwiftData
import Observation

/// RoutineSessionView 専用の状態管理。
/// 実際の進行ロジックは RoutineEngine / CharacterEngine を束ねる ConversationCoordinator に委譲し、
/// ここでは「画面に出す状態(progress, messages)を async 呼び出しの結果で更新する」ことだけを担当する。
@Observable
@MainActor
final class RoutineSessionViewModel {
    let routine: Routine
    private(set) var progress: RoutineProgress?
    private(set) var messages: [ConversationMessage] = []
    private(set) var characterName: String = "小悪魔コーチ"
    var inputText: String = ""

    /// キャラクターの返答を待っている間 true(チャットログの入力中インジケーターに使う)。
    private(set) var isCharacterThinking = false

    private var dependencies: AppDependencies?

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
        isCharacterThinking = true
        let turn = await dependencies.conversationCoordinator.start(routine: routine)
        isCharacterThinking = false
        progress = turn.progress
        appendCharacter(turn.characterText)
    }

    func complete() async { await record(.completed) }
    func skip() async { await record(.skipped) }
    func fail() async { await record(.failed) }

    private func record(_ outcome: StepOutcome) async {
        guard let dependencies, let progress, !progress.isFinished else { return }
        appendUser(outcome.userLabel)
        isCharacterThinking = true
        let turn = await dependencies.conversationCoordinator.recordOutcome(outcome, current: progress)
        isCharacterThinking = false
        self.progress = turn.progress
        appendCharacter(turn.characterText)
    }

    func askForHelp() async {
        guard let dependencies, let progress else { return }
        appendUser("助けて")
        isCharacterThinking = true
        let text = await dependencies.conversationCoordinator.askForHelp(current: progress)
        isCharacterThinking = false
        appendCharacter(text)
    }

    func submitFreeText() async {
        guard let dependencies, let progress else { return }
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        appendUser(text)
        isCharacterThinking = true
        let turn = await dependencies.conversationCoordinator.submitFreeText(text, current: progress)
        isCharacterThinking = false
        self.progress = turn.progress
        appendCharacter(turn.characterText)
    }

    func finishSession() {
        guard let dependencies, let progress, progress.session.status == .active else { return }
        dependencies.conversationCoordinator.abandon(progress)
    }

    private func appendUser(_ text: String) {
        messages.append(ConversationMessage(role: .user, text: text, timestamp: .now))
    }

    private func appendCharacter(_ text: String) {
        messages.append(ConversationMessage(role: .character, text: text, timestamp: .now))
    }
}
