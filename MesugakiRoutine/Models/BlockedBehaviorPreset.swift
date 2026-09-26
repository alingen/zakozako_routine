import Foundation
import FamilyControls

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
    let trackingKind: BlockedBehaviorTrackingKind
    let screenTimeLimitMinutes: Int

    init(
        id: String,
        title: String,
        iconName: String,
        limitRule: BlockedBehaviorLimitRule = .quitCompletely,
        trackingKind: BlockedBehaviorTrackingKind = .manual,
        screenTimeLimitMinutes: Int = 20
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.limitRule = limitRule
        self.trackingKind = trackingKind
        self.screenTimeLimitMinutes = min(max(screenTimeLimitMinutes, 1), 1_440)
    }

    static let all: [BlockedBehaviorPreset] = [
        BlockedBehaviorPreset(
            id: "no-smartphone",
            title: "スマホを見ない",
            iconName: "iphone",
            trackingKind: .screenTime,
            screenTimeLimitMinutes: 20
        ),
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
        BlockedBehaviorPreset(
            id: "no-gaming",
            title: "ゲームをしない",
            iconName: "gamecontroller"
        ),
    ]

    /// 初回オンボーディングで、最初に見直す習慣として提示する候補。
    /// 動画だけは続く内部画面で対象アプリと時間上限を設定し、Screen Time で自動判定する。
    static let onboarding: [BlockedBehaviorPreset] = [
        BlockedBehaviorPreset(
            id: "onboarding-stop-watching-videos",
            title: "動画をだらだら見る",
            iconName: "play.rectangle",
            trackingKind: .screenTime,
            screenTimeLimitMinutes: 20
        ),
        BlockedBehaviorPreset(
            id: "onboarding-view-social-media",
            title: "SNSを見る",
            iconName: "bubble.left.and.bubble.right"
        ),
        BlockedBehaviorPreset(
            id: "onboarding-smoking",
            title: "タバコを吸う",
            iconName: "lungs"
        ),
        BlockedBehaviorPreset(
            id: "onboarding-drink-alcohol",
            title: "お酒を飲む",
            iconName: "wineglass"
        ),
        BlockedBehaviorPreset(
            id: "onboarding-snacking",
            title: "間食をする",
            iconName: "birthday.cake"
        ),
    ]
}

/// 選択画面と確認画面の間だけで保持する、未保存の入力内容。
struct BlockedBehaviorDraft: Equatable {
    var title = ""
    var shareToZakoNews = false
    var iconName: String?
    var isQuitCompletely = true
    var limitPeriod: HabitPeriod = .day
    var limitCount = 1
    var trackingKind: BlockedBehaviorTrackingKind = .manual
    var screenTimeLimitMinutes = 20
    var screenTimeSelection = FamilyActivitySelection()

    init() {}

    init(behavior: BlockedBehavior) {
        title = behavior.title
        shareToZakoNews = behavior.shareToZakoNews
        iconName = behavior.iconName
        isQuitCompletely = behavior.limitPeriod == .day && behavior.effectiveLimit == 1
        limitPeriod = behavior.limitPeriod
        limitCount = behavior.effectiveLimit
        trackingKind = behavior.trackingKind
        screenTimeLimitMinutes = behavior.screenTimeLimitMinutes

        if let data = behavior.screenTimeSelectionData,
           let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            screenTimeSelection = selection
        }
    }

    var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        guard trackingKind == .screenTime else { return true }
        return hasScreenTimeTargets && screenTimeSelectionData != nil
    }

    var screenTimeSelectionData: Data? {
        try? JSONEncoder().encode(screenTimeSelection)
    }

    var screenTimeTargetCount: Int {
        screenTimeSelection.applicationTokens.count
            + screenTimeSelection.categoryTokens.count
            + screenTimeSelection.webDomainTokens.count
    }

    var effectiveLimitPeriod: HabitPeriod {
        isQuitCompletely ? .day : limitPeriod
    }

    var effectiveLimitCount: Int {
        isQuitCompletely ? 1 : max(limitCount, 1)
    }

    private var hasScreenTimeTargets: Bool {
        screenTimeTargetCount > 0
    }

    mutating func apply(_ preset: BlockedBehaviorPreset) {
        title = preset.title
        iconName = preset.iconName
        trackingKind = preset.trackingKind
        screenTimeLimitMinutes = preset.screenTimeLimitMinutes
        screenTimeSelection = FamilyActivitySelection()

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
