import Foundation

/// 「やらないこと」の上限ルール。プリセット内で矛盾した値を作らないための値型。
enum BlockedBehaviorLimitRule: Equatable {
    /// 1回でも行ったら、その日は失敗。
    case quitCompletely
    /// 指定期間内に `failureCount` 回行ったら失敗。
    case counted(period: HabitPeriod, failureCount: Int)

    var period: HabitPeriod {
        switch self {
        case .quitCompletely:
            return .day
        case let .counted(period, _):
            return period
        }
    }

    var failureCount: Int {
        switch self {
        case .quitCompletely:
            return 1
        case let .counted(_, failureCount):
            return max(failureCount, 1)
        }
    }
}

/// 新しい「やらないこと」を作るときに選べる入力済みテンプレート。
struct BlockedBehaviorPreset: Identifiable, Equatable {
    let id: String
    let title: String
    let iconName: String
    let limitRule: BlockedBehaviorLimitRule

    init(
        id: String,
        title: String,
        iconName: String,
        limitRule: BlockedBehaviorLimitRule = .quitCompletely
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.limitRule = limitRule
    }

    static let all: [BlockedBehaviorPreset] = [
        BlockedBehaviorPreset(
            id: "quit-smoking",
            title: "禁煙する",
            iconName: "lungs"
        ),
        BlockedBehaviorPreset(
            id: "quit-alcohol",
            title: "断酒する",
            iconName: "wineglass"
        ),
        BlockedBehaviorPreset(
            id: "stop-nose-picking",
            title: "鼻をほじらない",
            iconName: "hand.raised"
        ),
        BlockedBehaviorPreset(
            id: "avoid-junk-food",
            title: "ジャンクフードを食べない",
            iconName: "fork.knife"
        ),
        BlockedBehaviorPreset(
            id: "no-coffee",
            title: "コーヒーを飲まない",
            iconName: "cup.and.saucer"
        ),
        BlockedBehaviorPreset(
            id: "no-sweets",
            title: "甘いものをたべない",
            iconName: "birthday.cake"
        ),
        BlockedBehaviorPreset(
            id: "no-social-media",
            title: "SNSを見ない",
            iconName: "bubble.left.and.bubble.right"
        ),
        BlockedBehaviorPreset(
            id: "no-staying-up-late",
            title: "夜ふかしをしない",
            iconName: "moon.stars"
        ),
    ]
}

/// 選択画面と確認画面の間だけで保持する、未保存の入力内容。
struct BlockedBehaviorDraft: Equatable {
    var title = ""
    var iconName: String?
    var isQuitCompletely = true
    var limitPeriod: HabitPeriod = .day
    var limitCount = 1

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveLimitPeriod: HabitPeriod {
        isQuitCompletely ? .day : limitPeriod
    }

    var effectiveLimitCount: Int {
        isQuitCompletely ? 1 : max(limitCount, 1)
    }

    mutating func apply(_ preset: BlockedBehaviorPreset) {
        title = preset.title
        iconName = preset.iconName

        switch preset.limitRule {
        case .quitCompletely:
            isQuitCompletely = true
            limitPeriod = .day
            limitCount = 1
        case let .counted(period, failureCount):
            isQuitCompletely = false
            limitPeriod = period
            limitCount = max(failureCount, 1)
        }
    }

    mutating func reset() {
        self = BlockedBehaviorDraft()
    }
}
