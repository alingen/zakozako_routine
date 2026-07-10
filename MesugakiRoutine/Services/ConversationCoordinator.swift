import Foundation

/// Conversation Layer の中核。
///
/// UIフレームワーク(SwiftUI)には一切依存しない。ユーザーの操作(完了/スキップ/失敗/次なに？/助けて/自由入力)を
/// RoutineEngine に渡して進行状態を更新し、CharacterEngine から状況に応じた返答を取得して返すだけの薄い調停役。
/// 会話履歴(history)もここで保持し、ChatGPT等の会話APIに文脈として渡せるようにする。
///
/// この形にしておくことで、将来 RoutineSessionView がテキスト/ボタン操作から
/// OpenAI Realtime API を使った音声会話に差し替わっても、ConversationCoordinator の
/// メソッドシグネチャ(「操作を受けて Turn を返す」)はそのまま使い回せる。
@MainActor
final class ConversationCoordinator {
    /// 1回のやり取り(操作 → 進行状態更新 → キャラクター応答)の結果。
    struct Turn {
        let progress: RoutineProgress
        let characterText: String
    }

    private let routineEngine: RoutineEngine
    private let characterEngine: CharacterEngine
    private let blockedBehaviorRepository: BlockedBehaviorRepository

    /// このセッション中の会話履歴。AI応答生成のたびに文脈として渡し、応答後に追記する。
    /// 際限なく増えないよう直近40ターン程度に丸めている。
    private var history: [ConversationHistoryItem] = []

    init(
        routineEngine: RoutineEngine,
        characterEngine: CharacterEngine,
        blockedBehaviorRepository: BlockedBehaviorRepository
    ) {
        self.routineEngine = routineEngine
        self.characterEngine = characterEngine
        self.blockedBehaviorRepository = blockedBehaviorRepository
    }

    func start(routine: Routine) async -> Turn {
        let progress = routineEngine.startSession(for: routine)
        let response = await characterEngine.respond(
            to: .routineStarted(stepName: progress.currentStep?.title ?? ""),
            history: history
        )
        appendTurn(userLabel: "(ルーティン開始)", assistantText: response.text)
        return Turn(progress: progress, characterText: response.text)
    }

    func recordOutcome(_ outcome: StepOutcome, current progress: RoutineProgress) async -> Turn {
        let updated = routineEngine.recordOutcome(outcome, for: progress)

        let situation: CharacterSituation
        if updated.isFinished {
            situation = .routineCompleted
        } else {
            switch outcome {
            case .completed: situation = .stepCompleted(nextStepName: updated.currentStep?.title)
            case .skipped: situation = .stepSkipped(nextStepName: updated.currentStep?.title)
            case .failed: situation = .stepFailed(nextStepName: updated.currentStep?.title)
            }
        }
        let response = await characterEngine.respond(to: situation, history: history)
        appendTurn(userLabel: "(\(outcome.userLabel))", assistantText: response.text)
        return Turn(progress: updated, characterText: response.text)
    }

    func askNextStep(current progress: RoutineProgress) async -> String {
        let response = await characterEngine.respond(
            to: .nextStepQuery(currentStepName: progress.currentStep?.title),
            history: history
        )
        appendTurn(userLabel: "次なに？", assistantText: response.text)
        return response.text
    }

    func askForHelp(current progress: RoutineProgress) async -> String {
        guard let step = progress.currentStep else {
            let text = await characterEngine.respond(to: .routineCompleted, history: history).text
            appendTurn(userLabel: "助けて", assistantText: text)
            return text
        }
        let response = await characterEngine.respond(to: .helpRequested(currentStepName: step.title), history: history)
        appendTurn(userLabel: "助けて", assistantText: response.text)
        return response.text
    }

    /// 自由入力(テキスト/音声どちらの経路からも使う)を扱う。
    /// 完了フレーズ(`AppSettingsStore.completionPhrase`)に一致すればステップ完了として進め、
    /// 「やらないこと」に該当する発言ならブロック行動として記録し、それ以外は自由な会話として応答する。
    func submitFreeText(_ text: String, current progress: RoutineProgress) async -> Turn {
        if !progress.isFinished, matchesCompletionPhrase(text) {
            return await recordOutcome(.completed, current: progress)
        }

        if let behavior = blockedBehaviorRepository.firstMatch(for: text) {
            let response = await characterEngine.respond(
                to: .blockedBehaviorDetected(behaviorTitle: behavior.title, counterMessage: behavior.counterMessage),
                userText: text,
                history: history
            )
            routineEngine.recordBlockedBehavior(progress, userText: text, aiText: response.text)
            appendTurn(userLabel: text, assistantText: response.text)
            return Turn(progress: progress, characterText: response.text)
        } else {
            let response = await characterEngine.respond(to: .freeText(text), userText: text, history: history)
            appendTurn(userLabel: text, assistantText: response.text)
            return Turn(progress: progress, characterText: response.text)
        }
    }

    private func matchesCompletionPhrase(_ text: String) -> Bool {
        let phrase = AppSettingsStore.completionPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty else { return false }
        return text.localizedCaseInsensitiveContains(phrase)
    }

    func abandon(_ progress: RoutineProgress) {
        routineEngine.abandon(progress)
    }

    private func appendTurn(userLabel: String, assistantText: String) {
        history.append(ConversationHistoryItem(role: .user, text: userLabel))
        history.append(ConversationHistoryItem(role: .assistant, text: assistantText))
        if history.count > 40 {
            history.removeFirst(history.count - 40)
        }
    }
}
