import Foundation

/// AI API を使わず、ローカルのテンプレート文でキャラクター応答を生成する実装。
/// MVPではこれがデフォルトの `CharacterResponseGenerating` になる。
/// 将来ネットワーク越しのAI(OpenAI Realtime API等)に差し替える際は、
/// この struct と同じ protocol に準拠した別実装を用意して差し替えるだけでよい。
final class LocalCharacterResponseGenerator: CharacterResponseGenerating {

    /// 絶対に使ってはいけない表現(アプリ内設定にはせず、ここを直接編集してチューニングする)。
    static let forbiddenPhrases: [String] = []

    /// 積極的に使いたい推奨表現・語彙(アプリ内設定にはせず、ここを直接編集してチューニングする)。
    /// `OpenAICharacterResponseGenerator` がGPTへの語彙ガイドとして使う。ローカル応答はテンプレ文そのままなので参照しない。
    static let recommendedPhrases: [String] = ["♡", "ざっこ", "きっしょ", "つよつよ", "ざこざこ"]

    func generateResponse(context: CharacterResponseContext) async -> CharacterResponse {
        let rawText = templateText(for: context.situation)
        let safeText = ForbiddenPhraseFilter.apply(rawText, forbidden: Self.forbiddenPhrases)
        return CharacterResponse(text: safeText)
    }

    private func templateText(for situation: CharacterSituation) -> String {
        switch situation {
        case .routineStarted(let stepName):
            return "きっしょ〜♡\(stepName)からだって。このくらい大人なら余裕できるよね〜"

        case .stepCompleted(let nextStepName):
            if let next = nextStepName {
                return "ふぅん、まあこれくらいはらくしょ〜でしょ。次は\(next)ね〜"
            }
            return "ふぅん、これくらいはらくしょ〜でしょ"

        case .stepSkipped(let nextStepName):
            if let next = nextStepName {
                return "ざっこ〜♡こんなこともできないなんてざこざこメンタル♡次の\(next)くらいはできるよね〜？"
            }
            return "ざっこ〜♡こんなこともできないなんてざこざこメンタル♡"

        case .stepFailed(let nextStepName):
            if let next = nextStepName {
                return "まけみとめちゃうんだ〜ざっこ〜♡さすたに次の\(next)くらいはできるよね〜？"
            }
            return "まけみとめちゃうんだ〜ざっこ〜♡"

        case .routineCompleted:
            return "ふぅん、今日だけはつよつよってことにしといてあげる〜♡"

        case .helpRequested(let currentStepName):
            return "\(currentStepName)のやり方わかんないの？ざっこ〜♡ほら、体動かすだけでいいのに〜"

        case .blockedBehaviorDetected(_, let counterMessage):
            return counterMessage.isEmpty
                ? "え〜誘惑にまけてやっちゃうの？ざこざこめんたるでお先まっくら〜"
                : counterMessage

        case .nextStepQuery(let currentStepName):
            if let step = currentStepName {
                return "次の\(step)くらいは余裕でやってくれるよね〜？"
            }
            return "ふぅん、全部おわっちゃうなんてつよつよ〜"

        case .freeText:
            // 将来ここがAI(OpenAI等)による自由応答に置き換わる想定。
            return "うんうん、聞いてるよ。でも今はルーティンに集中しよっか。"
        }
    }

    /// 褒め方スタイルのサンプルセリフ(仮の文言。ここを直接編集してチューニングする)。
    /// `OpenAICharacterResponseGenerator` がGPTへの「褒め方の参考例」として使う。
    func sampleLine(for praiseStyle: PraiseStyle) -> String {
        switch praiseStyle {
        case .light:
            return "ふぅん、まあやるじゃん♡"
        case .teasing:
            return "え、ちゃんとできるんだ♡ちょっと見直しちゃうかも〜"
        case .honest:
            return "すっご〜♡さすがおとなだね〜ちょっと見直しちゃうかも〜"
        }
    }

    /// 叱り方スタイルのサンプルセリフ(仮の文言。ここを直接編集してチューニングする)。
    /// `OpenAICharacterResponseGenerator` がGPTへの「叱り方の参考例」として使う。
    func sampleLine(for scoldStyle: ScoldStyle) -> String {
        switch scoldStyle {
        case .gentle:
            return "まあ今回は見逃してあげる〜♡次はちゃんとやってよね？"
        case .provoking:
            return "ざっこ〜♡次こそやれるよね〜？"
        case .strict:
            return "はぁ？それはさすがにダメダメ〜♡次は言い訳なしでやってよね〜"
        }
    }
}
