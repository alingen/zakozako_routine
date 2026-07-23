import Foundation

/// フリートークの話題1つぶん。`question`をキャラクターから振り、その流れの中で`disclosure`(伝えたい情報)を
/// 会話に自然に組み込んで伝える。`question`は`FreeTalkTopicProgress`での完了管理のキーにもなる。
struct FreeTalkTopic: Equatable {
    let question: String
    let disclosure: String
}

/// フリートーク開始時にキャラクターから振る話題を、信頼度ステージ別に管理する。
/// 実際のセリフは `intro + 呼び名 + 質問` の形で組み立てる(組み立て自体は LocalCharacterResponseGenerator側)。
/// 中身はここを直接編集してチューニングする(アプリ内設定にはしない、他の口調チューニングと同じ方針)。
enum FreeTalkTopics {
    /// 質問の前に必ず付く決まり文句。この直後に呼び名、そして質問が続く。
    static let intro = "ひまだから特別に話してあげる〜♡"

    static let lowStage: [FreeTalkTopic] = [
        FreeTalkTopic(question: "どこに住んでるの〜？", disclosure: "わたしは東京都内に住んでる"),
        FreeTalkTopic(question: "ならいごとって何かしてる〜？", disclosure: "ダンスを習ってる"),
        FreeTalkTopic(question: "パパママと一緒に住んでるの〜？", disclosure: "パパもママも共働き"),
        FreeTalkTopic(question: "親友っているの〜？", disclosure: "幼稚園からの親友がいる"),
        FreeTalkTopic(question: "兄弟っているの〜？", disclosure: "ひとりっこ"),
    ]

    static let midStage: [FreeTalkTopic] = [
        FreeTalkTopic(question: "今日なんかあった？", disclosure: "最近ダンスの新しい振り付けを覚えてる"),
        FreeTalkTopic(question: "最近ハマってることある？", disclosure: "韓国系のファッションにハマってる"),
        FreeTalkTopic(question: "休みの日っていつも何してるの？", disclosure: "休みの日はだいたいダンスの練習してる"),
    ]

    static let highStage: [FreeTalkTopic] = [
        FreeTalkTopic(question: "最近どう？", disclosure: "最近ダンスの発表会に向けて忙しい"),
        FreeTalkTopic(question: "なんか悩みとかある？", disclosure: "人前で話すのがちょっと苦手"),
        FreeTalkTopic(question: "好きなものについてもっと教えてよ", disclosure: "K-POPのダンスが特に好き"),
    ]

    static func topics(for trustStage: Int) -> [FreeTalkTopic] {
        switch trustStage {
        case ...1: return lowStage
        case 2...3: return midStage
        default: return highStage
        }
    }
}

/// `FreeTalkTopics` から、まだ完了していない話題をランダムに1つ選ぶ。完了状況は
/// `FreeTalkTopicProgressRepository`で永続化されるため、同じ話題は完了するまで繰り返し選ばれうるが、
/// 完了した話題は選ばれなくなる。そのステージの話題を全て完了していれば nil を返す
/// (呼び出し側はステージ進行のトリガーとして扱う)。
@MainActor
enum FreeTalkTopicSelector {
    static func pickTopic(forStage stage: Int, progressRepository: FreeTalkTopicProgressRepository) -> FreeTalkTopic? {
        let topics = FreeTalkTopics.topics(for: stage)
        let incomplete = topics.filter { !progressRepository.isCompleted(question: $0.question) }
        return incomplete.randomElement()
    }
}
