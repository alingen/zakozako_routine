import Foundation

/// 交流ホームで莉央をタップしたときに使う仮セリフ。
/// 条件分岐を追加するときは、ここで表示候補を組み立ててViewへ渡す。
enum InteractionHomeDialogue {
    static let defaultLines = [
        "よわよわおにいさんがんばってね♡",
        "ざこなりにがんばって〜♡",
        "今回は何日もつかな〜？",
    ]

    static func nextIndex(after currentIndex: Int?, lineCount: Int = defaultLines.count) -> Int? {
        guard lineCount > 0 else { return nil }
        return ((currentIndex ?? -1) + 1) % lineCount
    }
}

/// View専用の不変値。CMS/SwiftDataモデルを直接変更せず、一覧表示に必要な情報だけを渡す。
struct StoryConditionPresentation: Identifiable, Hashable {
    let id: String
    let text: String
    let currentValue: String?
    let targetValue: String?
    let isSatisfied: Bool

    var progressText: String? {
        guard let currentValue, let targetValue else { return nil }
        return "\(currentValue) / \(targetValue)"
    }
}

struct StoryListItemPresentation: Identifiable, Hashable {
    let id: String
    let title: String
    let chapterId: String
    let episodeOrder: Int?
    let backgroundAssetId: String?
    let isUnlocked: Bool
    let isNew: Bool
    let isRead: Bool
    let conditions: [StoryConditionPresentation]
}

struct StoryChapterPresentation: Identifiable, Hashable {
    let id: String
    let title: String
    let stories: [StoryListItemPresentation]
}

struct StoryMemoryPresentation: Identifiable, Hashable {
    let id: String
    let title: String
    let assetId: String
    let isUnlocked: Bool
}
