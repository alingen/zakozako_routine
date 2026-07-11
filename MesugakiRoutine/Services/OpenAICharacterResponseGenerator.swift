import Foundation

/// OpenAI Chat Completions API を使ってキャラクター応答を生成する実装。
/// `CharacterResponseGenerating` に準拠しているだけなので、CharacterEngine / ConversationCoordinator
/// からは `LocalCharacterResponseGenerator` と区別なく扱われる。
///
/// APIキーが無い場合、またはネットワーク/APIエラー時は `fallback`(通常は Local 実装)に自動的に委譲し、
/// ルーティン進行そのものは止めない。
final class OpenAICharacterResponseGenerator: CharacterResponseGenerating {
    private let client: OpenAIChatCompletionsClient
    private let apiKeyProvider: () -> String?
    /// ローカルテンプレート実装。フォールバック応答だけでなく、状況別・褒め方/叱り方別の
    /// 「口調の参考例」の取得元としても使う(具体型で持つことで `sampleLine` を直接呼べるようにしている)。
    private let fallback: LocalCharacterResponseGenerator
    private let model: String

    init(
        client: OpenAIChatCompletionsClient = OpenAIChatCompletionsClient(),
        apiKeyProvider: @escaping () -> String?,
        fallback: LocalCharacterResponseGenerator = LocalCharacterResponseGenerator(),
        model: String = "gpt-4o-mini"
    ) {
        self.client = client
        self.apiKeyProvider = apiKeyProvider
        self.fallback = fallback
        self.model = model
    }

    func generateResponse(context: CharacterResponseContext) async -> CharacterResponse {
        guard let apiKey = apiKeyProvider(), !apiKey.isEmpty else {
            return await fallback.generateResponse(context: context)
        }

        // 状況に対する確立済みフレーズ(fallback = LocalCharacterResponseGenerator の出力)を、
        // GPTへの「口調の参考例」として使う。freeText(自由な会話)には参考例は使わない。
        var referenceLine = ""
        if case .freeText = context.situation {
            // no-op
        } else {
            referenceLine = await fallback.generateResponse(context: context).text
        }

        do {
            let text = try await client.send(
                messages: buildMessages(context: context, referenceLine: referenceLine),
                apiKey: apiKey,
                model: model
            )
            let safeText = ForbiddenPhraseFilter.apply(text, forbidden: LocalCharacterResponseGenerator.forbiddenPhrases)
            return CharacterResponse(text: safeText)
        } catch {
            // オフライン・レート制限・キー不正などの場合はローカル応答にフォールバックし、体験を止めない。
            return await fallback.generateResponse(context: context)
        }
    }

    private func buildMessages(context: CharacterResponseContext, referenceLine: String) -> [OpenAIChatMessage] {
        var messages = [OpenAIChatMessage(role: "system", content: systemPrompt(for: context.preset))]

        for item in context.history.suffix(20) {
            messages.append(OpenAIChatMessage(role: item.role == .user ? "user" : "assistant", content: item.text))
        }

        if case .freeText(let text) = context.situation {
            messages.append(OpenAIChatMessage(role: "user", content: text))
        } else {
            messages.append(OpenAIChatMessage(
                role: "system",
                content: situationInstruction(context.situation, referenceLine: referenceLine)
            ))
        }

        return messages
    }

    private func systemPrompt(for preset: CharacterPreset) -> String {
        var lines: [String] = []
        if !preset.basePrompt.isEmpty {
            lines.append(preset.basePrompt)
        }
        lines.append("キャラクター名: \(preset.name)")
        lines.append("褒め方のスタイル: \(preset.praiseStyle.displayName)(例: 「\(fallback.sampleLine(for: preset.praiseStyle))」)")
        lines.append("叱り方のスタイル: \(preset.scoldStyle.displayName)(例: 「\(fallback.sampleLine(for: preset.scoldStyle))」)")
        if !LocalCharacterResponseGenerator.forbiddenPhrases.isEmpty {
            lines.append("絶対に使ってはいけない表現: \(LocalCharacterResponseGenerator.forbiddenPhrases.joined(separator: "、"))")
        }
        if !LocalCharacterResponseGenerator.recommendedPhrases.isEmpty {
            lines.append("積極的に使いたい語彙・言い回し(自然に入る範囲で): \(LocalCharacterResponseGenerator.recommendedPhrases.joined(separator: "、"))")
        }
        lines.append("""
        ルール:
        - 生意気・軽い煽りのトーンで話すが、人格否定は絶対にしない
        - 性的表現は絶対に使わない
        - 要所要所にハートマーク(♡)を使う。辛辣な言葉でもハートを添えるだけで印象が丸くなる
        - 「応援してるからね」「頑張って」のような直接的な励ましの言葉で締めくくらない。\
        「大人なんだからこれくらいできるよね〜♡」のような、軽く煽る問いかけ・言い切りで終える程度でよく、\
        支援の気持ちは行間ににじませる程度にとどめ、言葉にしすぎない
        - ユーザーの行動を促すが、傷つける言い方にはしない
        - 返答は日本語で2文以内の短い一言にする
        - 各指示に添えられる「参考にする言い回し」は、このキャラの確立された口調そのものを表す例。\
        状況にぴったり合う場合はほぼそのまま使ってよく、状況が少し違う・自由な会話の場合は\
        一字一句同じでなくてよいので同じ語尾・言葉選び・テンションで新しく作って返す
        """)
        return lines.joined(separator: "\n")
    }

    /// ボタン操作などUIイベント由来の状況を、モデルへの指示文に変換する。
    /// `referenceLine` は同じ状況に対する `LocalCharacterResponseGenerator` の確立済みフレーズで、
    /// テンプレでカバーしきれない細かな状況でもキャラのトーンを保ったままLLMに補完してもらうための参考例。
    /// `.freeText` はユーザーの生発言としてそのまま渡すため、ここでは扱わない。
    private func situationInstruction(_ situation: CharacterSituation, referenceLine: String) -> String {
        let instruction: String
        switch situation {
        case .routineStarted(let stepName):
            instruction = "ユーザーがルーティンを開始した。最初のステップは「\(stepName)」。取り組むよう一言で煽って促して。"
        case .stepCompleted(let next):
            if let next {
                instruction = "ユーザーが現在のステップを完了した。次のステップは「\(next)」。軽く褒めつつ次に促して。"
            } else {
                instruction = "ユーザーが現在のステップを完了した。軽く褒めて。"
            }
        case .stepSkipped(let next):
            if let next {
                instruction = "ユーザーが現在のステップをスキップした。次のステップは「\(next)」。軽く煽りつつ次に促して。"
            } else {
                instruction = "ユーザーが現在のステップをスキップした。軽く流して。"
            }
        case .stepFailed(let next):
            if let next {
                instruction = "ユーザーが現在のステップをできなかった。次のステップは「\(next)」。励ましつつ切り替えさせて。"
            } else {
                instruction = "ユーザーが現在のステップをできなかった。励まして。"
            }
        case .routineCompleted:
            instruction = "ユーザーが全ステップを完了し、ルーティンが終わった。しっかり褒めて締めくくって。"
        case .helpRequested(let current):
            instruction = "ユーザーが助けを求めている。今のステップは「\(current)」。それだけに集中すればいいと伝えて安心させて。"
        case .blockedBehaviorDetected(let title, let counter, let alternativeAction):
            var text = "ユーザーが「やらない」と決めていた行動(\(title))をしようとしている。次のメッセージのニュアンスを踏まえて短く止めて: \(counter)"
            if !alternativeAction.isEmpty {
                text += " 止めるだけでなく、代わりに「\(alternativeAction)」を軽く勧めて。"
            }
            instruction = text
        case .nextStepQuery(let current):
            if let current {
                instruction = "ユーザーが次にやることを聞いている。今のステップは「\(current)」だと伝えて。"
            } else {
                instruction = "ユーザーが次にやることを聞いているが、もう全ステップ終わっている。その旨を伝えて。"
            }
        case .homeGreeting(let streakDays, let isMorningRoutinePending):
            if isMorningRoutinePending {
                instruction = "ユーザーがホーム画面を開いたが、今日の朝ルーティンをまだ始めていない時間帯になっている。サボりを軽く指摘して急かして。"
            } else {
                instruction = "ユーザーがホーム画面を開いた。継続\(streakDays)日目。日数に応じてからかい半分に迎えて(1日目なら今更感、日数が増えるほど少しずつ認めつつ煽る)。"
            }
        case .freeText:
            instruction = ""
        }

        guard !referenceLine.isEmpty else { return instruction }
        return instruction + "\n参考にする言い回し: 「\(referenceLine)」"
    }
}
