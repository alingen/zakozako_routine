import Foundation

/// 交流ホームで莉央をタップしたときに使う仮セリフ。
/// 条件分岐を追加するときは、ここで表示候補を組み立ててViewへ渡す。
enum InteractionHomeDialogue {
    static let defaultLines = [
        "がんばってね、ざこざこおにいさん♡",
        "また負けちゃったんだ、ざ〜こ♡",
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

/// The current main chapter's read stories, not a mock day count or a lifetime total.
/// A chapter advances only after all of its stories have been read.
struct InteractionStoryProgressPresentation: Equatable {
    let chapterTitle: String
    let completedCount: Int
    let totalCount: Int
    let nextStoryText: String

    var progressFraction: Double {
        guard totalCount > 0 else { return 0 }
        return min(max(Double(completedCount) / Double(totalCount), 0), 1)
    }

    static let empty = Self(
        chapterTitle: "ストーリー",
        completedCount: 0,
        totalCount: 0,
        nextStoryText: "ストーリー準備中"
    )

    static func make(
        chapters: [StoryChapterPresentation],
        evaluations: [StoryEventUnlockEvaluation]
    ) -> Self {
        let nonemptyChapters = chapters.filter { !$0.stories.isEmpty }
        guard let chapter = nonemptyChapters.first(where: { $0.stories.contains { !$0.isRead } })
            ?? nonemptyChapters.last else { return .empty }

        let completedCount = chapter.stories.filter(\.isRead).count
        let nextStory = chapter.stories.first { !$0.isRead }
        let nextStoryText: String
        if let nextStory {
            nextStoryText = nextText(
                story: nextStory,
                evaluation: evaluations.first { $0.id == nextStory.id }
            )
        } else {
            nextStoryText = "すべてのストーリーを読み終えました"
        }
        return Self(
            chapterTitle: chapter.title,
            completedCount: completedCount,
            totalCount: chapter.stories.count,
            nextStoryText: nextStoryText
        )
    }

    private static func nextText(
        story: StoryListItemPresentation,
        evaluation: StoryEventUnlockEvaluation?
    ) -> String {
        if story.isUnlocked { return "次のストーリーを読めます" }
        guard let evaluation else { return "解放条件を確認してください" }
        guard evaluation.evaluation.accessDecision.isAllowed else {
            return "ストーリーの利用条件を確認してください"
        }

        let unmet = evaluation.conditions.filter { !$0.satisfied }
        guard !unmet.isEmpty else { return "解放条件を確認してください" }
        var remainingDays = 0
        var remainingTrust = 0
        for result in unmet {
            // Unknown/missing values and non-increasing comparisons cannot
            // truthfully be turned into an estimated number of days.
            guard result.diagnostic == nil,
                  let amount = remainingAmount(for: result) else {
                return "解放条件を確認してください"
            }
            let condition = result.condition
            if condition.conditionType == "streak",
               ["continuous_days", "streak_days", "streak"].contains(condition.conditionKey) {
                remainingDays = max(remainingDays, amount)
            } else if ["cumulative_days", "total_days"].contains(condition.conditionKey),
                      ["cumulative", "achievement"].contains(condition.conditionType) {
                remainingDays = max(remainingDays, amount)
            } else if condition.conditionType == "relationship", condition.conditionKey == "trust" {
                remainingTrust = max(remainingTrust, amount)
            } else {
                return "解放条件を確認してください"
            }
        }
        var remaining: [String] = []
        if remainingDays > 0 { remaining.append("あと\(remainingDays)日") }
        if remainingTrust > 0 { remaining.append("信頼度あと\(remainingTrust)") }
        guard !remaining.isEmpty else { return "解放条件を確認してください" }
        return "次のストーリーまで " + remaining.joined(separator: "・")
    }

    private static func remainingAmount(for evaluation: StoryConditionEvaluation) -> Int? {
        guard let currentText = evaluation.current,
              let current = Double(currentText), let threshold = Double(evaluation.threshold),
              current.isFinite, threshold.isFinite else { return nil }
        let target: Double
        switch evaluation.condition.operator {
        case .greaterThanOrEqual:
            target = ceil(threshold)
        case .greaterThan:
            target = floor(threshold) + 1
        case .equal where threshold.rounded() == threshold && current < threshold:
            target = threshold
        default:
            return nil
        }
        let difference = ceil(target - current)
        guard difference > 0, difference < Double(Int.max) else { return nil }
        return Int(difference)
    }
}

struct StoryMemoryPresentation: Identifiable, Hashable {
    let id: String
    let title: String
    let assetId: String
    let isUnlocked: Bool
}
