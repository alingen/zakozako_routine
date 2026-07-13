import Foundation

/// フリートーク開始時にキャラクターから振る質問を、信頼度ステージ別に管理する。
/// 実際のセリフは `intro + 呼び名 + 質問` の形で組み立てる(組み立て自体は LocalCharacterResponseGenerator側)。
/// 中身はここを直接編集してチューニングする(アプリ内設定にはしない、他の口調チューニングと同じ方針)。
enum FreeTalkTopics {
    /// 質問の前に必ず付く決まり文句。この直後に呼び名、そして質問が続く。
    static let intro = "ひまだから特別に話してあげる〜♡"

    static let lowStage: [String] = [
        "どこに住んでるの〜？",
        "ならいごとって何かしてる〜？",
        "パパママと一緒に住んでるの〜？",
        "ともだちっているの〜？",
    ]

    static let midStage: [String] = [
        "今日なんかあった？",
        "最近ハマってることある？",
        "休みの日っていつも何してるの？",
    ]

    static let highStage: [String] = [
        "最近どう？",
        "なんか悩みとかある？",
        "好きなものについてもっと教えてよ",
    ]

    static func topics(for trustStage: Int) -> [String] {
        switch trustStage {
        case ...1: return lowStage
        case 2...3: return midStage
        default: return highStage
        }
    }
}

/// `FreeTalkTopics` から、まだ選んでいない話題をランダムに1つ選ぶ。選んだ話題は使用済みとして記録し、
/// 同じ話題が続けて出てこないようにする。1つの信頼度ステージ内の話題を全て使い切ったら、
/// そのステージぶんの記録だけリセットしてまた選べるようにする。
enum FreeTalkTopicSelector {
    private static let usedTopicsKey = "used_free_talk_topics"

    private static var usedTopics: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: usedTopicsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: usedTopicsKey) }
    }

    static func pickTopic(forTrustStage trustStage: Int) -> String? {
        let topics = FreeTalkTopics.topics(for: trustStage)
        guard !topics.isEmpty else { return nil }

        var used = usedTopics
        var candidates = topics.filter { !used.contains($0) }
        if candidates.isEmpty {
            for topic in topics { used.remove(topic) }
            candidates = topics
        }

        guard let picked = candidates.randomElement() else { return nil }
        used.insert(picked)
        usedTopics = used
        return picked
    }
}
