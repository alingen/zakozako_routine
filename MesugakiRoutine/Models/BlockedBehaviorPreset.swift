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
            id: "no-harsh-words",
            title: "悪態をつかない",
            iconName: "bubble.left"
        ),
        BlockedBehaviorPreset(
            id: "improve-posture",
            title: "猫背をやめる",
            iconName: "figure.stand"
        ),
        BlockedBehaviorPreset(
            id: "stop-nail-biting",
            title: "爪を噛まない",
            iconName: "hand.raised"
        ),
        BlockedBehaviorPreset(
            id: "stop-nose-picking",
            title: "鼻をほじらない",
            iconName: "hand.raised"
        ),
        BlockedBehaviorPreset(
            id: "reduce-alcohol",
            title: "アルコールの消費量を減らす",
            iconName: "wineglass",
            limitRule: .counted(period: .week, failureCount: 4)
        ),
        BlockedBehaviorPreset(
            id: "no-coffee",
            title: "コーヒーを飲まない",
            iconName: "cup.and.saucer"
        ),
        BlockedBehaviorPreset(
            id: "avoid-unhealthy-food",
            title: "体に悪い食べ物を避ける",
            iconName: "fork.knife"
        ),
        BlockedBehaviorPreset(
            id: "no-procrastination",
            title: "先延ばしにしない",
            iconName: "hourglass"
        ),
        BlockedBehaviorPreset(
            id: "less-phone",
            title: "スマホを見すぎない",
            iconName: "phone.down"
        ),
        BlockedBehaviorPreset(
            id: "no-impulse-buying",
            title: "衝動買いをしない",
            iconName: "cart"
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
