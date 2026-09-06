import Foundation

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
