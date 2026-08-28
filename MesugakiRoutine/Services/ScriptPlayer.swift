import Foundation
import Observation

/// 台本(`ConversationScript`)を1メッセージずつ再生する共通エンジン。
///
/// 今日の会話・小イベント・(将来の)大イベントで共有する。UIフレームワークやSwiftDataには依存せず、
/// 「選択肢で保存すると指定された情報の永続化」だけ `UserProfileFactRepository` に委譲する。
/// 再生し終えたら `onFinished` を1度だけ呼ぶ。台本を進めた/完了した副作用(会話インデックスの前進、
/// イベントの完了記録など)は呼び出し側が `onFinished` で行う。
@Observable
@MainActor
final class ScriptPlayer {
    private(set) var messages: [ConversationMessage] = []
    private(set) var isCharacterTyping = false
    /// 非nilなら選択肢を提示中。ユーザーがどれか選ぶまで再生を止める。
    private(set) var pendingChoices: [ScriptChoice]?
    private(set) var isFinished = false
    /// いま表示中の台本メッセージ。大イベント画面が背景/立ち絵/話者名を組み立てるのに使う。
    private(set) var currentMessage: ScriptMessage?
    /// いま表示中のメッセージ本文(`{{fact:}}` 置換済み)。選択肢の反映(ユーザー発言)は含まない。
    private(set) var currentText: String = ""

    private let script: ConversationScript
    private let factRepository: UserProfileFactRepository
    /// true: キャラ発言を「入力中」演出付きで自動送りする(今日の会話・小イベント)。
    /// false: 1メッセージ表示するたびに停止し、`advance()` の呼び出し(タップ)で次へ進む(大イベント)。
    private let autoAdvance: Bool
    /// 現在の関係性フェーズ。メッセージの `minPhase` / `maxPhase` 判定に使う。
    private let relationshipPhase: Int
    private let onFinished: () -> Void

    private var hasStarted = false

    init(
        script: ConversationScript,
        factRepository: UserProfileFactRepository,
        autoAdvance: Bool = true,
        relationshipPhase: Int = 0,
        onFinished: @escaping () -> Void
    ) {
        self.script = script
        self.factRepository = factRepository
        self.autoAdvance = autoAdvance
        self.relationshipPhase = relationshipPhase
        self.onFinished = onFinished
    }

    /// このメッセージを現在の関係性フェーズで表示してよいか。
    private func isVisible(_ message: ScriptMessage) -> Bool {
        if let min = message.minPhase, relationshipPhase < min { return false }
        if let max = message.maxPhase, relationshipPhase > max { return false }
        return true
    }

    /// この選択肢を、保存済みユーザー情報に照らして表示してよいか。
    private func isChoiceAvailable(_ choice: ScriptChoice) -> Bool {
        guard let req = choice.requirement else { return true }
        let current = factRepository.allFacts[req.key]
        switch req.op {
        case .exists:
            return current != nil
        case .eq:
            return current == req.value
        case .ne:
            return current != req.value
        case .gt, .gte, .lt, .lte:
            guard let currentValue = current.flatMap(Double.init),
                  let target = Double(req.value) else { return false }
            switch req.op {
            case .gt: return currentValue > target
            case .gte: return currentValue >= target
            case .lt: return currentValue < target
            case .lte: return currentValue <= target
            default: return false
            }
        }
    }

    /// `start` から辿って、表示条件を満たす最初のメッセージを返す(合わないものは飛ばす)。
    private func firstVisible(from message: ScriptMessage?) -> ScriptMessage? {
        var cursor = message
        while let current = cursor {
            if isVisible(current) { return current }
            cursor = script.message(after: current)
        }
        return nil
    }

    /// 再生を開始する。二重開始はガードする。台本が空なら読み込み失敗として扱い、`onFinished` は呼ばない。
    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        guard let first = firstVisible(from: script.first) else {
            messages.append(ConversationMessage(role: .character, text: "(会話データを読み込めませんでした)", timestamp: .now))
            isFinished = true
            return
        }
        await play(first)
    }

    /// 提示中の選択肢からユーザーが1つ選んだ時に呼ぶ。
    /// `saveFact` 指定があれば、選択結果をユーザープロフィール情報として保存する
    /// (別の会話のメッセージ内で `{{fact:キー}}` として参照できる)。
    func selectChoice(_ choice: ScriptChoice) async {
        guard let current = currentMessage else { return }
        pendingChoices = nil
        if let fact = choice.saveFact {
            factRepository.upsert(key: fact.key, value: fact.value)
        }
        messages.append(ConversationMessage(role: .user, text: choice.text, timestamp: .now))

        let rawNext: ScriptMessage?
        if let nextID = choice.next {
            rawNext = script.message(id: nextID)
        } else {
            rawNext = script.message(after: current)
        }
        guard let next = firstVisible(from: rawNext) else { finish(); return }
        if autoAdvance {
            try? await Task.sleep(for: .milliseconds(350))
        }
        await play(next)
    }

    /// 手動送り(大イベント)。いま表示中のメッセージの次へ進める。選択肢提示中は無効。
    func advance() async {
        guard !autoAdvance, pendingChoices == nil, !isFinished, let current = currentMessage else { return }
        guard let next = firstVisible(from: script.message(after: current)) else {
            finish()
            return
        }
        await play(next)
    }

    private func play(_ message: ScriptMessage) async {
        currentMessage = message
        currentText = resolvePlaceholders(message.text)

        // 本文が空のテキストノード(選択肢だけを出すためのノード等)は吹き出しを出さない。
        let hasVisibleBubble = message.type == .image || !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if hasVisibleBubble, message.speaker == .character, autoAdvance {
            isCharacterTyping = true
            try? await Task.sleep(for: .milliseconds(650))
            isCharacterTyping = false
        }
        if hasVisibleBubble {
            appendFromScript(message)
        }

        if let fact = message.saveFact {
            factRepository.upsert(key: fact.key, value: fact.value)
        }

        if let choices = message.choices, !choices.isEmpty {
            let available = choices.filter(isChoiceAvailable)
            if !available.isEmpty {
                pendingChoices = available
                return
            }
            // 条件を満たす選択肢が1つも無い場合は、選択肢を出さずにそのまま次へ進む。
        }

        guard autoAdvance else { return }

        guard let next = firstVisible(from: script.message(after: message)) else {
            finish()
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        await play(next)
    }

    private func appendFromScript(_ message: ScriptMessage) {
        let role: ConversationMessage.Role = message.speaker == .character ? .character : .user
        messages.append(
            ConversationMessage(
                role: role,
                text: resolvePlaceholders(message.text),
                timestamp: .now,
                imageName: message.type == .image ? message.imageName : nil
            )
        )
    }

    /// メッセージ本文中の `{{fact:キー}}` / `{{fact:キー|代替文}}` を、保存済みユーザー情報の値に置き換える。
    private func resolvePlaceholders(_ text: String) -> String {
        guard text.contains("{{fact:") else { return text }
        let facts = factRepository.allFacts
        let pattern = #"\{\{fact:([A-Za-z0-9_]+)(?:\|([^}]*))?\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: result),
                  let keyRange = Range(match.range(at: 1), in: result) else { continue }
            let key = String(result[keyRange])
            var fallback = ""
            if let fallbackRange = Range(match.range(at: 2), in: result) {
                fallback = String(result[fallbackRange])
            }
            result.replaceSubrange(fullRange, with: facts[key] ?? fallback)
        }
        return result
    }

    private func finish() {
        guard !isFinished else { return }
        isFinished = true
        onFinished()
    }
}
