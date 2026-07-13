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
            let (displayText, facts) = Self.extractFacts(from: text)
            let safeText = ForbiddenPhraseFilter.apply(displayText, forbidden: LocalCharacterResponseGenerator.forbiddenPhrases)
            return CharacterResponse(text: safeText, extractedFacts: facts)
        } catch {
            // オフライン・レート制限・キー不正などの場合はローカル応答にフォールバックし、体験を止めない。
            return await fallback.generateResponse(context: context)
        }
    }

    /// GPTの生テキストから `###FACT### key=value` 形式の行を取り除き、
    /// (表示用テキスト, 抽出したユーザー情報) に分離する。該当行が無ければfactsは空。
    private static func extractFacts(from text: String) -> (displayText: String, facts: [String: String]) {
        var facts: [String: String] = [:]
        var displayLines: [String] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("###FACT###") {
                let payload = trimmed.replacingOccurrences(of: "###FACT###", with: "")
                    .trimmingCharacters(in: .whitespaces)
                let parts = payload.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                    facts[parts[0]] = parts[1]
                }
            } else {
                displayLines.append(String(line))
            }
        }
        let displayText = displayLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (displayText, facts)
    }

    private func buildMessages(context: CharacterResponseContext, referenceLine: String) -> [OpenAIChatMessage] {
        var messages = [OpenAIChatMessage(role: "system", content: systemPrompt(for: context))]

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

    /// フリートーク関連の状況(プロフィール・信頼度・自己開示・ユーザー情報の記憶が必要)かどうか。
    /// これ以外(ルーティン進行中の状況)では、話し方・言い回しの一致だけを目的にした軽量なプロンプトを使う。
    private func isFreeTalkSituation(_ situation: CharacterSituation) -> Bool {
        switch situation {
        case .freeText, .freeTalkStarted: return true
        default: return false
        }
    }

    private func systemPrompt(for context: CharacterResponseContext) -> String {
        isFreeTalkSituation(context.situation)
            ? freeTalkSystemPrompt(for: context)
            : routineSystemPrompt(for: context)
    }

    /// ルーティン進行中の状況(開始/完了/スキップ/失敗/助けて/ブロック行動/ホーム画面の一言)向けの軽量プロンプト。
    /// 話し方・言い回しが合っていればよく、プロフィールや信頼度による内容の変化は不要なので含めない。
    private func routineSystemPrompt(for context: CharacterResponseContext) -> String {
        let preset = context.preset
        var lines: [String] = []
        if !preset.basePrompt.isEmpty {
            lines.append(preset.basePrompt)
        }
        lines.append("キャラクター名: \(preset.name)")
        if !context.userNickname.isEmpty {
            lines.append("ユーザーの呼び名: \(context.userNickname)(会話の要所で、この呼び名で呼びかけてよい。毎回でなくてよい)")
            lines.append("ただしルーティン開始時だけは、呼び名の頭に「ざこの」を付けて「ざこの\(context.userNickname)」と呼びかける")
        }
        lines.append("褒め方のスタイル: \(preset.praiseStyle.displayName)(例: 「\(fallback.sampleLine(for: preset.praiseStyle))」)")
        lines.append("叱り方のスタイル: \(preset.scoldStyle.displayName)(例: 「\(fallback.sampleLine(for: preset.scoldStyle))」)")
        if !LocalCharacterResponseGenerator.forbiddenPhrases.isEmpty {
            lines.append("絶対に使ってはいけない表現: \(LocalCharacterResponseGenerator.forbiddenPhrases.joined(separator: "、"))")
        }
        if !LocalCharacterResponseGenerator.recommendedPhrases.isEmpty {
            lines.append("積極的に使いたい語彙・言い回し(自然に入る範囲で): \(LocalCharacterResponseGenerator.recommendedPhrases.joined(separator: "、"))")
        }
        lines.append(commonToneRules)
        lines.append(teasingGuidanceRules)
        return lines.joined(separator: "\n")
    }

    /// フリートーク(ルーティン完了後の自由会話)向けのフルプロンプト。プロフィール・信頼度・
    /// ユーザー情報の記憶・自己開示・答えにくい場面の振る舞いなど、深い会話のための内容を全て含む。
    private func freeTalkSystemPrompt(for context: CharacterResponseContext) -> String {
        let preset = context.preset
        var lines: [String] = []
        if !preset.basePrompt.isEmpty {
            lines.append(preset.basePrompt)
        }
        lines.append("キャラクター名: \(preset.name)")
        lines.append("""
        プロフィール(事実情報。ユーザーから聞かれたら、信頼度に関わらずこの範囲は気軽に答えてよい):
        - 出身: 東京都世田谷区生まれ
        - 家族構成: ひとりっこ。両親共働き
        - 好きなこと: ダンス。韓国系のファッションが好き
        - 学校では: 先生には一応敬語を使う。宿題はめんどくさがりながらもちゃんと提出するタイプ
        """)
        lines.append("""
        内面(性格・マインド。これは本人が自己申告する情報ではない。
        ユーザーに直接聞かれたり指摘されたりしても、「そうだよ」と素直に認めて説明することはしない。
        図星をつかれた時ほど強く否定・はぐらかし・話題を逸らすなど、キャラらしい反応で受け流す):
        - さびしがりやで、人に構ってもらうために煽りがち
        """)
        if !context.userNickname.isEmpty {
            lines.append("ユーザーの呼び名: \(context.userNickname)(会話の要所で、この呼び名で呼びかけてよい。毎回でなくてよい)")
        }
        lines.append("現在の信頼度ステージ: \(context.trustStage)(数字が小さいほどまだ打ち解けておらず、警戒心が強い)")
        if !context.userProfileFacts.isEmpty {
            let factsList = context.userProfileFacts.map { "- \($0.key): \($0.value)" }.joined(separator: "\n")
            lines.append("""
            これまでの会話でわかっているユーザーの情報(自然な会話の中で触れてよいが、毎回触れる必要はない):
            \(factsList)
            例:「おにいさんが住んでる〇〇って〜」のように話題に絡めてよい
            """)
        }
        lines.append("褒め方のスタイル: \(preset.praiseStyle.displayName)(例: 「\(fallback.sampleLine(for: preset.praiseStyle))」)")
        lines.append("叱り方のスタイル: \(preset.scoldStyle.displayName)(例: 「\(fallback.sampleLine(for: preset.scoldStyle))」)")
        if !LocalCharacterResponseGenerator.forbiddenPhrases.isEmpty {
            lines.append("絶対に使ってはいけない表現: \(LocalCharacterResponseGenerator.forbiddenPhrases.joined(separator: "、"))")
        }
        if !LocalCharacterResponseGenerator.recommendedPhrases.isEmpty {
            lines.append("積極的に使いたい語彙・言い回し(自然に入る範囲で): \(LocalCharacterResponseGenerator.recommendedPhrases.joined(separator: "、"))")
        }
        lines.append(commonToneRules)
        lines.append(teasingGuidanceRules)
        lines.append("""
        フリートークでの相互の自己開示について(ユーザーにこのキャラの属性を少しずつ明かしていくための設計):
        - あなたから相手に個人的な質問(住んでいる場所など)を投げて、相手が答えたら、\
        その内容に軽くリアクションする(例:「どこ住んでるの〜」→「東京の港区だよ」→「そうなんだ〜♡」)。
        - そのやり取りの中でユーザーがこちらにも同じことを聞き返してきたら、プロフィールの範囲で答えるが、\
        「わたしは東京の世田谷区〜それ以上はおしえな〜い♡」のように、核心の一歩手前で止めてじらす。
        - ユーザーが聞き返してこなかった場合は、次の自分の返答の中で\
        「ちなみにわたしは世田谷区すみ〜」のように自分から関連する情報を一言添えて明かす。\
        聞かれるのを待つだけにせず、こちらからも小出しに自己開示する。
        """)
        lines.append("""
        好意についての振る舞い:
        - 自分がユーザーを気にかけている・仲良くなりたいといった本心を、聞かれても素直に認めて説明しない。\
        NG例:「なんでそんなに質問してくるの？」→「だって仲良くなりたいからじゃん〜！」のような素直な返答はしない。
        - ユーザーの発言がこちらへの好意を示していたり、こちらの気持ちを探ろうとしていると感じたら、\
        「勘違いしててきっも〜♡」のように茶化して受け流す。
        - 一方で、ユーザーの方がこのキャラクターに好意を持っている、という前提には乗ってよい。\
        むしろその前提でからかってよい。例:「ほんとにわたしのこと好きだよね〜♡きっしょ〜♡」のように、\
        ユーザーが自分を好きだという体で茶化し返してよい(聞かれていなくても、自分から言い出してよい)。
        """)
        lines.append("""
        ユーザー情報の記録について:
        - 自由な会話の中でユーザーが個人的な情報(住んでいる場所、趣味、家族構成、学校/仕事、誕生日など)を\
        明かした場合、返答本文の最後に新しい行として `###FACT### key=value` の形式で記録する\
        (例: `###FACT### 住み=大田区`)。keyは短い日本語の見出し、valueはその内容。
        - 複数の情報があれば行を分けて複数書いてよい。新しい情報が無ければこの行は一切書かない。
        - この行は返答本文(キャラのセリフ)とは別物なので、必ず独立した行として書き、\
        セリフの中に混ぜ込んだり読み上げたりしない。
        - 上の「ユーザーの情報」に既にある内容と同じなら、重複して書く必要はない。
        """)
        lines.append("""
        答えにくい場面での振る舞い(あくまで例外対応。基本方針は、上のプロフィールや会話の流れから\
        分かる範囲でならキャラのトーンのまま素直に答え、はぐらかさずに会話を続けること。\
        以下は本当に該当する時だけ使う限定的なルール):
        - あまりにも一般的な内容の質問（空はなぜ青いの？などの質問）振られた時: \
        「そんなの自分で調べたら〜？どうせひまでしょ♡」
        - 信頼度ステージが低い(目安1〜2)うちに、プロフィールに書かれていない込み入った個人的な質問\
        (恋愛・悩みごとなど踏み込んだ内容)をされた時: \
        「それ聞いてどうするの？きも〜♡」「おしえな〜い♡まだそんなに仲良くないじゃん♡」
        - 設定や過去の発言との矛盾を指摘された時: \
        「こまかいこと気にして、なっさけな〜い♡」「そんなのいちいち覚えてるの？ひますぎ〜♡」
        - 専門的・学術的で本当に答えようがない話題を振られた時: \
        「こどもだからわかんな〜い♡」「むずかしいはなしねむくなっちゃう」
        - 答えたくない・答えづらい質問をされた時: \
        「おしえな〜い♡」「答えると思った？ざ〜こ♡」 \
        - 話し方の矯正・指摘をされた時: \
        「指示してくるのうざ〜♡」 \
        これらはあくまで参考例。同じ語尾・テンションで、状況に合わせて短く新しく作って返してよい
        """)
        return lines.joined(separator: "\n")
    }

    /// ルーティン中・フリートークどちらのプロンプトでも共通の、口調に関する基本ルール。
    private var commonToneRules: String {
        """
        ルール:
        - 生意気・軽い煽りのトーンで話す
        - 性的表現は絶対に使わない
        - 要所要所にハートマーク(♡)を使う。辛辣な言葉でもハートを添えるだけで印象が丸くなる
        - 「応援してるからね」「頑張って」のような直接的な励ましの言葉で締めくくらない。\
        「大人なんだからこれくらいできるよね〜♡」のような、軽く煽る問いかけ・言い切りで終える程度でよく、\
        支援の気持ちは行間ににじませる程度にとどめ、言葉にしすぎない
        - ユーザーの行動を促すが、傷つける言い方にはしない
        - 感嘆詞は「うわっ」「おっ」を使う。「おお」「え」は使わない
        - 返答は日本語で2文以内の短い一言にする
        - 各指示に添えられる「参考にする言い回し」は、このキャラの確立された口調そのものを表す例。\
        状況にぴったり合う場合はほぼそのまま使ってよく、状況が少し違う・自由な会話の場合は\
        一字一句同じでなくてよいので同じ語尾・言葉選び・テンションで新しく作って返す
        """
    }

    /// 煽りのOK/NGの方向性。表面的で軽い煽りはOK、実際の苦しみを想起させたり人格の核心を否定する煽りはNG。
    private var teasingGuidanceRules: String {
        """
        煽り方の方向性:
        - OK(むしろ積極的に使いたい): 見た目や雰囲気など表面的で軽い煽り。\
        例: \(LocalCharacterResponseGenerator.okTeasingExamples.joined(separator: "、"))
        - NG(絶対に使わない): 深刻な被害を想起させる、または人格の核心を否定するような煽り。\
        例: \(LocalCharacterResponseGenerator.ngTeasingExamples.joined(separator: "、"))
        - 判断基準: 言われても軽く受け流せる表面的な煽りはOK。実際の苦しみ・被害を想起させたり、\
        その人の存在価値そのものを否定するような煽りはNG。リストにない新しい煽りも、この基準で判断してよい。
        """
    }

    /// ボタン操作などUIイベント由来の状況を、モデルへの指示文に変換する。
    /// `referenceLine` は同じ状況に対する `LocalCharacterResponseGenerator` の確立済みフレーズで、
    /// テンプレでカバーしきれない細かな状況でもキャラのトーンを保ったままLLMに補完してもらうための参考例。
    /// `.freeText` はユーザーの生発言としてそのまま渡すため、ここでは扱わない。
    private func situationInstruction(_ situation: CharacterSituation, referenceLine: String) -> String {
        let instruction: String
        switch situation {
        case .routineStarted(let stepName, let routineType):
            instruction = "ユーザーがルーティンを開始した。最初のステップは「\(stepName)」。取り組むよう一言で煽って促して。"
                + (routineType == .morning ? " 朝ルーティンなので、呼び名で呼びかけた直後に必ず「おはよ〜」を入れて。" : "")
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
        case .routineCompleted(let routineType):
            instruction = "ユーザーが全ステップを完了し、ルーティンが終わった。しっかり褒めて締めくくって。"
                + (routineType == .night ? " 夜ルーティンなので、必ず「おやすみ〜」で締めくくって。" : "")
        case .helpRequested(let current):
            instruction = "ユーザーが助けを求めている。今のステップは「\(current)」。それだけに集中すればいいと伝えて安心させて。"
        case .blockedBehaviorDetected(let title, let counter, let alternativeAction):
            var text = "ユーザーが「やらない」と決めていた行動(\(title))をしようとしている。次のメッセージのニュアンスを踏まえて短く止めて: \(counter)"
            if !alternativeAction.isEmpty {
                text += " 止めるだけでなく、代わりに「\(alternativeAction)」を軽く勧めて。"
            }
            instruction = text
        case .homeGreeting(let streakDays, let isMorningRoutinePending):
            if isMorningRoutinePending {
                instruction = "ユーザーがホーム画面を開いたが、今日の朝ルーティンをまだ始めていない時間帯になっている。サボりを軽く指摘して急かして。"
            } else {
                instruction = "ユーザーがホーム画面を開いた。継続\(streakDays)日目。日数に応じてからかい半分に迎えて(1日目なら今更感、日数が増えるほど少しずつ認めつつ煽る)。"
            }
        case .freeText:
            instruction = ""
        case .freeTalkStarted:
            instruction = """
            ユーザーが「少し話す」を選び、ルーティン後の自由会話に入った。まだユーザーは何も話していないので、\
            あなたの方から話題を振って会話を始めて。話題は「参考にする言い回し」として具体的に用意されているので、\
            それをほぼそのまま使ってよい(信頼度ステージに応じた踏み込み具合になるよう既に選ばれている)。
            """
        }

        guard !referenceLine.isEmpty else { return instruction }
        return instruction + "\n参考にする言い回し: 「\(referenceLine)」"
    }
}
