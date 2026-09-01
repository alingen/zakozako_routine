import Foundation

/// Conversation Layer の中核。
///
/// UIフレームワーク(SwiftUI)には一切依存しない。ユーザーの操作(完了/スキップ/失敗/助けて/自由入力)を
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
        /// この操作でルーティンが完了した場合のみ非nil。完了体験(Presentation)の構築に使う。
        var completion: RoutineCompletionResult?

        init(progress: RoutineProgress, characterText: String, completion: RoutineCompletionResult? = nil) {
            self.progress = progress
            self.characterText = characterText
            self.completion = completion
        }
    }

    /// フリートークでの1往復の結果。`closingLine`が非nilの場合、その回で話すべき話題(伝達事項)を
    /// 伝え終えたことを示す。呼び出し側(ViewModel)は`replyText`と`closingLine`を別々の吹き出しとして
    /// 表示することで、AIが2通に分けて送ってきたかのような見た目にできる。`closingLine`が非nilの場合は
    /// フリートークモードを終了させ、「少し話す/今日は終わる」の選択に戻してよい。
    struct FreeTalkTurn {
        let replyText: String
        let closingLine: String?
        var shouldEndFreeTalk: Bool { closingLine != nil }

        /// 音声読み上げなど、まとめて1つの文字列として扱いたい場面向け。
        var text: String {
            guard let closingLine else { return replyText }
            return replyText + "\n" + closingLine
        }
    }

    private let routineEngine: RoutineEngine
    private let characterEngine: CharacterEngine
    private let blockedBehaviorRepository: BlockedBehaviorRepository
    private let trustRepository: TrustRepository
    private let userProfileFactRepository: UserProfileFactRepository
    private let freeTalkTopicProgressRepository: FreeTalkTopicProgressRepository
    /// ルーティン完了の副作用(Trust 加算・イベント再評価)はすべてここに委譲する。
    private let routineCompletionService: RoutineCompletionService

    /// このセッション中の会話履歴。AI応答生成のたびに文脈として渡し、応答後に追記する。
    /// 際限なく増えないよう直近40ターン程度に丸めている。
    private var history: [ConversationHistoryItem] = []

    /// 直前のフリートーク開始時に振った話題のうち、まだ伝え終えていないもの。
    /// `freeTalk` の応答で伝え終えたと判定されたら nil に戻す。
    private var pendingDisclosureTopic: FreeTalkTopic?

    init(
        routineEngine: RoutineEngine,
        characterEngine: CharacterEngine,
        blockedBehaviorRepository: BlockedBehaviorRepository,
        trustRepository: TrustRepository,
        userProfileFactRepository: UserProfileFactRepository,
        freeTalkTopicProgressRepository: FreeTalkTopicProgressRepository,
        routineCompletionService: RoutineCompletionService
    ) {
        self.routineEngine = routineEngine
        self.characterEngine = characterEngine
        self.blockedBehaviorRepository = blockedBehaviorRepository
        self.trustRepository = trustRepository
        self.userProfileFactRepository = userProfileFactRepository
        self.freeTalkTopicProgressRepository = freeTalkTopicProgressRepository
        self.routineCompletionService = routineCompletionService
    }

    /// `characterEngine.respond` の薄いラッパー。GPT応答から抽出されたユーザー情報があれば、
    /// どの状況経由でも漏れなく永続化されるよう、応答取得は必ずこれを通す。
    private func respond(
        to situation: CharacterSituation,
        userText: String? = nil
    ) async -> CharacterResponse {
        let response = await characterEngine.respond(
            to: situation,
            userText: userText,
            pendingDisclosure: pendingDisclosureTopic?.disclosure,
            history: history
        )
        for (key, value) in response.extractedFacts {
            userProfileFactRepository.upsert(key: key, value: value)
        }
        return response
    }

    func start(routine: Routine) async -> Turn {
        let progress = routineEngine.startSession(for: routine)
        let response = await respond(
            to: .routineStarted(routineTitle: routine.title, stepName: progress.currentStep?.title ?? "")
        )
        appendTurn(userLabel: "(ルーティン開始)", assistantText: response.text)
        return Turn(progress: progress, characterText: response.text)
    }

    func recordOutcome(_ outcome: StepOutcome, current progress: RoutineProgress) async -> Turn {
        let updated = routineEngine.recordOutcome(outcome, for: progress)

        let situation: CharacterSituation
        var completionResult: RoutineCompletionResult?
        if updated.isFinished {
            // 完了副作用(Trust +1 / イベント再評価)は共通サービスに一本化。
            // RoutineEngine が既にセッションを .completed にした後で呼ぶこと。
            let result = routineCompletionService.applyCompletionSideEffects(routineId: updated.routine.id)
            completionResult = result
            situation = .routineCompleted(
                routineTitle: updated.routine.title,
                allRoutinesCompletedToday: result.allRoutinesCompletedToday
            )
        } else {
            switch outcome {
            case .completed: situation = .stepCompleted(nextStepName: updated.currentStep?.title)
            case .skipped: situation = .stepSkipped(nextStepName: updated.currentStep?.title)
            case .failed: situation = .stepFailed(nextStepName: updated.currentStep?.title)
            }
        }
        let response = await respond(to: situation)
        appendTurn(userLabel: "(\(outcome.userLabel))", assistantText: response.text)
        return Turn(progress: updated, characterText: response.text, completion: completionResult)
    }

    func askForHelp(current progress: RoutineProgress) async -> String {
        guard let step = progress.currentStep else {
            let text = await respond(to: .routineCompleted(
                routineTitle: progress.routine.title,
                allRoutinesCompletedToday: routineCompletionService.allTodayRoutinesCompleted()
            )).text
            appendTurn(userLabel: "助けて", assistantText: text)
            return text
        }
        let response = await respond(to: .helpRequested(currentStepName: step.title))
        appendTurn(userLabel: "助けて", assistantText: response.text)
        return response.text
    }

    /// 自由入力(テキスト/音声どちらの経路からも使う)を扱う。
    /// 完了フレーズ(`AppSettingsStore.completionPhrase`)に一致すればステップ完了として進め、
    /// 「やらないこと」に該当する発言ならブロック行動として記録し、それ以外はルーティンと無関係な話題として
    /// 固定の一言で受け流す(AIを呼ばない。ルーティン中の雑談はキャラの深い設定を必要としないため)。
    func submitFreeText(_ text: String, current progress: RoutineProgress) async -> Turn {
        if !progress.isFinished, matchesCompletionPhrase(text) {
            return await recordOutcome(.completed, current: progress)
        }

        if let behavior = blockedBehaviorRepository.firstMatch(for: text) {
            let response = await respond(
                to: .blockedBehaviorDetected(
                    behaviorTitle: behavior.title,
                    counterMessage: behavior.counterMessage,
                    reason: behavior.reason,
                    alternativeAction: behavior.alternativeAction
                ),
                userText: text
            )
            routineEngine.recordBlockedBehavior(progress, userText: text, aiText: response.text)
            appendTurn(userLabel: text, assistantText: response.text)
            return Turn(progress: progress, characterText: response.text)
        } else {
            let responseText = LocalCharacterResponseGenerator.offTopicDuringRoutineReply
            appendTurn(userLabel: text, assistantText: responseText)
            return Turn(progress: progress, characterText: responseText)
        }
    }

    /// フリートークモードに入った直後、信頼度ステージに応じた未完了の話題を1つ選んで振る。
    /// ユーザーの発言ではないため信頼度は変化しない。
    func beginFreeTalk() async -> FreeTalkTurn {
        let topic = FreeTalkTopicSelector.pickTopic(
            forStage: trustRepository.stage,
            progressRepository: freeTalkTopicProgressRepository
        )
        pendingDisclosureTopic = topic
        let response = await respond(to: .freeTalkStarted(topic: topic))
        let turn = makeFreeTalkTurn(from: response)
        appendTurn(userLabel: "(フリートーク開始)", assistantText: turn.text)
        return turn
    }

    /// ルーティン完了後の自由会話(フリートーク)を扱う。RoutineProgressに紐づかないため
    /// ステップ進行やブロック行動判定は行わず、キャラクターとの雑談として応答するだけ。
    /// やり取りのたびに信頼度が+1される。保留中の話題の伝達事項を伝え終えたら完了扱いにし、
    /// ステージ進行の条件も揃っていれば次のステージに進める。話すべき話題を伝え終えた回は、
    /// キャラクターの返答に続けて締めの挨拶を添え、フリートークをこちらから終了させる。
    func freeTalk(_ text: String) async -> FreeTalkTurn {
        let response = await respond(to: .freeText(text), userText: text)
        let turn = makeFreeTalkTurn(from: response)
        appendTurn(userLabel: text, assistantText: turn.text)
        trustRepository.increment(by: 1)
        trustRepository.tryAdvanceStage(topicProgressRepository: freeTalkTopicProgressRepository)
        return turn
    }

    /// キャラクター応答から`FreeTalkTurn`を組み立てる。話すべき話題を伝え終えた回は、返答本体(疑問形の
    /// 末尾があれば取り除いたもの)と締めの挨拶を別々の吹き出しとして扱えるよう分けて保持する。
    private func makeFreeTalkTurn(from response: CharacterResponse) -> FreeTalkTurn {
        guard completePendingDisclosureIfNeeded(response) else {
            return FreeTalkTurn(replyText: response.text, closingLine: nil)
        }
        return FreeTalkTurn(
            replyText: Self.removingTrailingQuestion(from: response.text),
            closingLine: freeTalkClosingLine()
        )
    }

    /// 保留中の話題を伝え終えていれば完了として記録し、伝え終えたかどうかを返す。
    private func completePendingDisclosureIfNeeded(_ response: CharacterResponse) -> Bool {
        guard response.disclosureCompleted, let topic = pendingDisclosureTopic else { return false }
        freeTalkTopicProgressRepository.markCompleted(question: topic.question)
        pendingDisclosureTopic = nil
        return true
    }

    /// 話すべき話題を伝え終えた時にキャラクターから添える締めの一言。
    private func freeTalkClosingLine() -> String {
        "じゃあ今日はここまでね〜ざこなりに今日も頑張ってね♡"
    }

    /// 文末の句読点(。！？!?)の直後に続く装飾・空白文字(♡〜~ー等)までを1文としてまとめて分割する。
    private static func splitIntoSentenceChunks(_ text: String) -> [String] {
        let terminators: Set<Character> = ["。", "！", "？", "!", "?"]
        let decorations: Set<Character> = ["♡", "〜", "~", "ー"]
        var chunks: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            current.append(character)
            index = text.index(after: index)
            guard terminators.contains(character) else { continue }
            while index < text.endIndex, decorations.contains(text[index]) || text[index].isWhitespace {
                current.append(text[index])
                index = text.index(after: index)
            }
            chunks.append(current)
            current = ""
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    /// `disclosed == true` の回に締めの挨拶をつなげる前に使う保険的な後処理。
    /// モデルへは「今伝えるべき情報を伝えた回は質問で終わらせない」と指示しているが、遵守されないことがあり、
    /// その場合そのまま締めの挨拶をつなげると「質問→即座に会話終了」という不自然な流れになってしまう。
    /// 返答が複数文(句読点で区切れる)かつ最後の文が疑問形の場合、その最後の文だけを取り除く。
    /// 疑問形の1文しかない場合は、空にしてしまうより元の文をそのまま残す。
    private static func removingTrailingQuestion(from text: String) -> String {
        let chunks = splitIntoSentenceChunks(text)
        guard chunks.count > 1, let last = chunks.last, last.contains("？") || last.contains("?") else {
            return text
        }
        return chunks.dropLast().joined().trimmingCharacters(in: .whitespacesAndNewlines)
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
