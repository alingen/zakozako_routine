import Foundation
import FamilyControls
import Observation

/// 専用オンボーディング画面（6画面）の現在位置。
enum OnboardingSetupStep: Int, Codable, CaseIterable, Sendable {
    case introduction = 0
    case habitSelection = 1
    case goalSetting = 2
    case cueSelection = 3
    // 既存保存データの confirmation = 4 を維持するため、新画面には未使用値を割り当てる。
    case blockedBehaviorSelection = 5
    case confirmation = 4

    static let allCases: [OnboardingSetupStep] = [
        .introduction,
        .habitSelection,
        .goalSetting,
        .cueSelection,
        .blockedBehaviorSelection,
        .confirmation,
    ]

    var orderIndex: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }
}

/// 1枚目のアプリ紹介・名前入力から、莉央との出会いを段階的に表示する現在位置。
enum OnboardingIntroductionStage: String, Codable, Sendable {
    case appIntroduction
    case nameEntry
    case firstMessage
    case secondMessage
    case characterExplanation
}

/// 2枚目で習慣を選んだ後、莉央の説明を段階的に表示する現在位置。
enum OnboardingHabitSelectionStage: String, Codable, Sendable {
    case awaitingSelection
    // 直前の実装で保存された `rioMessage` も、最初のセリフとしてそのまま復元する。
    case firstMessage = "rioMessage"
    case secondMessage
    case systemExplanation
    case completed
}

/// 3・4枚目で、補足説明を1回だけ重ねる進行状態。
enum OnboardingDelayedGuidanceStage: String, Codable, Sendable {
    case waitingToPresent
    case presented
    case explanation
    case completed
}

/// 「やらないこと」画面の、選択前後に表示する莉央の案内位置。
enum OnboardingBlockedBehaviorStage: String, Codable, Sendable {
    case waitingToPresent
    case firstMessage
    case secondMessage
    case awaitingSelection
    case screenTimeConfiguration
    case postSelectionFirstMessage
    case postSelectionSecondMessage
    case systemExplanation
    case completed
}

/// 最終確認画面で、莉央の会話と約束の確認方法を段階的に表示する現在位置。
enum OnboardingConfirmationGuidanceStage: String, Codable, Sendable {
    case waitingToPresent
    case firstMessage
    case secondMessage
    case explanation
    case completed
}

/// 専用画面終了後を含む、オンボーディング全体の現在位置。
enum OnboardingPhase: String, Codable, Sendable {
    case dedicatedSetup
    case prologue
    case prologueMessage
    case firstReport
    case conversationPrompt
    case storyUnlockPresentation
    case firstStoryPlayback
    case firstStoryReadConfirmation
    case tomorrowPromise
    case tomorrowRioMessage
    case completed
}

enum OnboardingFirstReportOutcome: String, Codable, Sendable {
    case completed
    case deferred
}

enum OnboardingConversationChoice: String, Codable, Sendable {
    case started
    case later
}

/// オンボーディングで選ばれた「最初の会話」の固定識別子。
///
/// 日付が変わっても同じシナリオとセーブ位置を再開できるよう、日次スケジュールから
/// 毎回選び直さず、この組み合わせをオンボーディング完了後も完読まで保持する。
struct OnboardingConversationIdentity: Codable, Equatable, Sendable {
    let scenarioID: String
    let playbackKey: String
}

enum OnboardingNotificationChoice: String, Codable, Sendable {
    case enabled
    case notNow
}

/// OS権限要求から通知予約完了までの途中状態。
/// アプリが中断されても「今はしない」で変更前へ戻せるよう、変更前の値も保持する。
struct OnboardingNotificationSetup: Codable, Equatable, Sendable {
    let routineID: UUID
    var reminderMinuteOfDay: Int
    var notBefore: Date
    let originalScheduledStartMinute: Int?
    let originalNotificationsEnabled: Bool
}

/// オンボーディングで選択した、まだ保存前の「やらないこと」。
struct OnboardingBlockedBehaviorDraft: Codable, Equatable, Sendable {
    static let customID = "custom"
    static let noneID = "none"
    static let screenTimeVideoID = "onboarding-stop-watching-videos"

    var selectionID: String
    var title: String
    var iconName: String?
    /// 追加前の保存データをそのまま復元できるよう、Screen Time項目はoptionalで保持する。
    var screenTimeLimitMinutes: Int? = nil
    var screenTimeSelectionData: Data? = nil

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isNone: Bool { selectionID == Self.noneID }
    var shouldCreate: Bool { !isNone && !trimmedTitle.isEmpty }
    var usesScreenTime: Bool { selectionID == Self.screenTimeVideoID }
    var effectiveScreenTimeLimitMinutes: Int {
        min(max(screenTimeLimitMinutes ?? 20, 5), 720)
    }
    var screenTimeTargetCount: Int {
        guard let screenTimeSelectionData,
              let selection = try? JSONDecoder().decode(
                  FamilyActivitySelection.self,
                  from: screenTimeSelectionData
              ) else { return 0 }
        return selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }
    var hasValidScreenTimeConfiguration: Bool {
        !usesScreenTime || screenTimeTargetCount > 0
    }
}

/// 6画面で入力する内容。実データを作成するまでは UserDefaults にだけ保持する。
struct OnboardingDraft: Codable, Equatable, Sendable {
    var userName: String

    /// プリセットまたは `custom` を識別する、UI側で安定したID。
    var selectedHabitID: String?
    /// 条件を付ける前の習慣名（例: 「本を読む」）。
    var habitTitle: String
    var habitIconName: String?

    /// 条件プリセットまたは `custom` を識別するID。
    var selectedGoalID: String?
    /// 画面表示用の達成条件（例: 「5分」）。
    var goalText: String
    /// Routine.title に保存する具体化済みタイトル（例: 「本を5分読む」）。
    var routineTitle: String

    /// タイミングプリセットまたは `custom` を識別するID。
    var selectedCueID: String?
    /// Routine.cueText に保存する実行タイミング（例: 「寝る前」）。
    var cueText: String

    /// 最終フェーズで選んだ通知時刻。0時からの分数（0...1439）。
    var reminderMinuteOfDay: Int?

    /// 最初に挑戦する「やらないこと」。特にない場合も sentinel 値を保持する。
    var blockedBehavior: OnboardingBlockedBehaviorDraft?

    init(
        userName: String = "",
        selectedHabitID: String? = nil,
        habitTitle: String = "",
        habitIconName: String? = nil,
        selectedGoalID: String? = nil,
        goalText: String = "",
        routineTitle: String = "",
        selectedCueID: String? = nil,
        cueText: String = "",
        reminderMinuteOfDay: Int? = nil,
        blockedBehavior: OnboardingBlockedBehaviorDraft? = nil
    ) {
        self.userName = userName
        self.selectedHabitID = selectedHabitID
        self.habitTitle = habitTitle
        self.habitIconName = habitIconName
        self.selectedGoalID = selectedGoalID
        self.goalText = goalText
        self.routineTitle = routineTitle
        self.selectedCueID = selectedCueID
        self.cueText = cueText
        self.reminderMinuteOfDay = reminderMinuteOfDay.map(Self.normalizedMinuteOfDay)
        self.blockedBehavior = blockedBehavior
    }

    var trimmedUserName: String {
        userName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedRoutineTitle: String {
        routineTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedCueText: String {
        cueText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasIdentity: Bool { !trimmedUserName.isEmpty }

    var hasHabitSelection: Bool {
        selectedHabitID != nil
            && !habitTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasConcreteGoal: Bool {
        selectedGoalID != nil && !trimmedRoutineTitle.isEmpty
    }

    var hasCueSelection: Bool {
        selectedCueID != nil && !trimmedCueText.isEmpty
    }

    var hasBlockedBehaviorSelection: Bool {
        guard let blockedBehavior else { return false }
        return blockedBehavior.isNone || !blockedBehavior.trimmedTitle.isEmpty
    }

    mutating func setReminderMinuteOfDay(_ minute: Int?) {
        reminderMinuteOfDay = minute.map(Self.normalizedMinuteOfDay)
    }

    private static func normalizedMinuteOfDay(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}

/// オンボーディングの入力内容と進行を、アプリ終了をまたいで復元するストア。
///
/// Routine の実データは6画面目で通常Repositoryへ保存し、このストアにはそのIDだけを保持する。
@Observable
@MainActor
final class OnboardingStateStore {
    nonisolated static let defaultStorageKey = "onboarding_state_v1"

    nonisolated private static let schemaVersion = 1

    private(set) var setupStep: OnboardingSetupStep {
        didSet { persistIfNeeded() }
    }
    private(set) var introductionStage: OnboardingIntroductionStage {
        didSet { persistIfNeeded() }
    }
    private(set) var habitSelectionStage: OnboardingHabitSelectionStage {
        didSet { persistIfNeeded() }
    }
    private(set) var goalSettingGuidanceStage: OnboardingDelayedGuidanceStage {
        didSet { persistIfNeeded() }
    }
    private(set) var cueSelectionGuidanceStage: OnboardingDelayedGuidanceStage {
        didSet { persistIfNeeded() }
    }
    private(set) var blockedBehaviorStage: OnboardingBlockedBehaviorStage {
        didSet { persistIfNeeded() }
    }
    private(set) var confirmationGuidanceStage: OnboardingConfirmationGuidanceStage {
        didSet { persistIfNeeded() }
    }
    private(set) var prologueMessageSecondLineShown: Bool {
        didSet { persistIfNeeded() }
    }
    private(set) var phase: OnboardingPhase {
        didSet { persistIfNeeded() }
    }
    var draft: OnboardingDraft {
        didSet { persistIfNeeded() }
    }
    private(set) var createdRoutineID: UUID? {
        didSet { persistIfNeeded() }
    }
    private(set) var firstReportOutcome: OnboardingFirstReportOutcome? {
        didSet { persistIfNeeded() }
    }
    private(set) var conversationChoice: OnboardingConversationChoice? {
        didSet { persistIfNeeded() }
    }
    private(set) var conversationIdentity: OnboardingConversationIdentity? {
        didSet { persistIfNeeded() }
    }
    private(set) var notificationChoice: OnboardingNotificationChoice? {
        didSet { persistIfNeeded() }
    }
    private(set) var notificationRoutineID: UUID? {
        didSet { persistIfNeeded() }
    }
    private(set) var notificationNotBefore: Date? {
        didSet { persistIfNeeded() }
    }
    private(set) var pendingNotificationSetup: OnboardingNotificationSetup? {
        didSet { persistIfNeeded() }
    }
    private(set) var isPrologueAutoplayPending: Bool {
        didSet { persistIfNeeded() }
    }
    /// 初回報告のCoach Markが、実際に画面へ表示されたことがあるか。
    private(set) var tutorialReportShown: Bool {
        didSet { persistIfNeeded() }
    }
    /// 達成または「あとでやる」により、初回報告の操作説明を終えたか。
    private(set) var tutorialReportCompleted: Bool {
        didSet { persistIfNeeded() }
    }
    private(set) var isCompleted: Bool {
        didSet { persistIfNeeded() }
    }

    /// このストアを作った時点で、オンボーディング状態がまだ一度も保存されていなかったか。
    ///
    /// 既存バージョンから更新したユーザーを初回オンボーディングで遮らないための
    /// 移行判定にだけ使い、オンボーディング途中の状態とは分けて扱う。
    @ObservationIgnored private(set) var startedWithoutSavedState: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let storageKey: String
    @ObservationIgnored private var isBatchUpdating = false

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = OnboardingStateStore.defaultStorageKey
    ) {
        self.defaults = defaults
        self.storageKey = storageKey

        let restoredSnapshot = Self.loadSnapshot(defaults: defaults, storageKey: storageKey)
        startedWithoutSavedState = restoredSnapshot == nil
        let snapshot = restoredSnapshot ?? .initial
        let restoredAsCompleted = snapshot.isCompleted || snapshot.phase == .completed
        setupStep = snapshot.setupStep
        introductionStage = snapshot.introductionStage ?? .nameEntry
        habitSelectionStage = snapshot.habitSelectionStage
            ?? Self.restoredHabitSelectionStage(from: snapshot)
        goalSettingGuidanceStage = Self.restoredDelayedGuidanceStage(
            snapshot.goalSettingGuidanceStage,
            for: .goalSetting,
            setupStep: snapshot.setupStep
        )
        cueSelectionGuidanceStage = Self.restoredDelayedGuidanceStage(
            snapshot.cueSelectionGuidanceStage,
            for: .cueSelection,
            setupStep: snapshot.setupStep
        )
        blockedBehaviorStage = snapshot.blockedBehaviorStage
            ?? Self.restoredBlockedBehaviorStage(from: snapshot)
        confirmationGuidanceStage = snapshot.confirmationGuidanceStage
            ?? Self.restoredConfirmationGuidanceStage(from: snapshot)
        prologueMessageSecondLineShown = snapshot.prologueMessageSecondLineShown ?? false
        // 旧版では「あとでやる」だけで会話案内へ進んでいた。まだ選択していない場合は
        // 初回報告へ戻し、実際の達成を待つ。
        phase = !restoredAsCompleted
            && snapshot.phase == .conversationPrompt
            && snapshot.firstReportOutcome == .deferred
            && snapshot.conversationChoice == nil
            ? .firstReport
            : snapshot.phase
        draft = snapshot.draft
        createdRoutineID = snapshot.createdRoutineID
        firstReportOutcome = snapshot.firstReportOutcome
        conversationChoice = snapshot.conversationChoice
        conversationIdentity = snapshot.conversationIdentity
        notificationChoice = snapshot.notificationChoice
        notificationRoutineID = snapshot.notificationRoutineID
        notificationNotBefore = snapshot.notificationNotBefore
        pendingNotificationSetup = snapshot.pendingNotificationSetup
        isPrologueAutoplayPending = snapshot.isPrologueAutoplayPending ?? false
        let restoredReportTutorialCompleted = (
            snapshot.tutorialReportCompleted ?? (snapshot.firstReportOutcome != nil)
        ) || restoredAsCompleted
        tutorialReportCompleted = restoredReportTutorialCompleted
        tutorialReportShown = (snapshot.tutorialReportShown
            ?? restoredReportTutorialCompleted) || restoredReportTutorialCompleted

        // 完了状態とphaseの片方だけが保存された瞬間に終了しても、再起動時に完了を維持する。
        isCompleted = restoredAsCompleted
        if restoredAsCompleted {
            phase = .completed
        }
    }

    var shouldPresentDedicatedSetup: Bool {
        !isCompleted && phase == .dedicatedSetup
    }

    var isRunningInAppTutorial: Bool {
        !isCompleted && phase != .dedicatedSetup
    }

    var shouldPresentReportTutorial: Bool {
        !isCompleted && phase == .firstReport && !tutorialReportCompleted
    }

    func canContinue(from step: OnboardingSetupStep? = nil) -> Bool {
        switch step ?? setupStep {
        case .introduction:
            return introductionStage == .appIntroduction || draft.hasIdentity
        case .habitSelection:
            return draft.hasHabitSelection
        case .goalSetting:
            return draft.hasConcreteGoal && goalSettingGuidanceStage == .completed
        case .cueSelection:
            return draft.hasCueSelection && cueSelectionGuidanceStage == .completed
        case .blockedBehaviorSelection:
            guard draft.hasBlockedBehaviorSelection else { return false }
            switch blockedBehaviorStage {
            case .awaitingSelection, .completed:
                return true
            case .screenTimeConfiguration:
                return draft.blockedBehavior?.hasValidScreenTimeConfiguration == true
            case .waitingToPresent,
                 .firstMessage,
                 .secondMessage,
                 .postSelectionFirstMessage,
                 .postSelectionSecondMessage,
                 .systemExplanation:
                return false
            }
        case .confirmation:
            return draft.hasCueSelection
                && (draft.blockedBehavior?.hasValidScreenTimeConfiguration ?? true)
                && confirmationGuidanceStage == .completed
        }
    }

    func goToSetupStep(_ step: OnboardingSetupStep) {
        guard !isCompleted else { return }
        performBatchUpdate {
            phase = .dedicatedSetup
            setupStep = step
            if step == .introduction {
                introductionStage = .nameEntry
                habitSelectionStage = .awaitingSelection
            } else if step == .habitSelection {
                habitSelectionStage = draft.selectedHabitID == nil ? .awaitingSelection : .completed
            } else if step == .blockedBehaviorSelection {
                blockedBehaviorStage = draft.hasBlockedBehaviorSelection
                    ? .awaitingSelection
                    : .waitingToPresent
            }
        }
    }

    func selectBlockedBehavior(_ selection: OnboardingBlockedBehaviorDraft) {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .blockedBehaviorSelection else { return }
        performBatchUpdate {
            draft.blockedBehavior = selection
            if blockedBehaviorStage == .completed {
                blockedBehaviorStage = .awaitingSelection
            }
        }
    }

    func updateBlockedBehaviorScreenTimeConfiguration(
        selectionData: Data?,
        limitMinutes: Int
    ) {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .blockedBehaviorSelection,
              var blockedBehavior = draft.blockedBehavior,
              blockedBehavior.usesScreenTime else { return }
        blockedBehavior.screenTimeSelectionData = selectionData
        blockedBehavior.screenTimeLimitMinutes = min(max(limitMinutes, 5), 720)
        draft.blockedBehavior = blockedBehavior
    }

    func presentBlockedBehaviorGuidanceIfNeeded() {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .blockedBehaviorSelection,
              blockedBehaviorStage == .waitingToPresent else { return }
        blockedBehaviorStage = .firstMessage
    }

    func presentConfirmationGuidanceIfNeeded() {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .confirmation,
              confirmationGuidanceStage == .waitingToPresent else { return }
        confirmationGuidanceStage = .firstMessage
    }

    func advanceConfirmationGuidance() {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .confirmation else { return }
        switch confirmationGuidanceStage {
        case .firstMessage:
            confirmationGuidanceStage = .secondMessage
        case .secondMessage:
            confirmationGuidanceStage = .explanation
        case .explanation:
            confirmationGuidanceStage = .completed
        case .waitingToPresent, .completed:
            break
        }
    }

    func retreatConfirmationGuidance() {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .confirmation else { return }
        switch confirmationGuidanceStage {
        case .explanation:
            confirmationGuidanceStage = .secondMessage
        case .secondMessage:
            confirmationGuidanceStage = .firstMessage
        case .firstMessage:
            confirmationGuidanceStage = .completed
        case .waitingToPresent, .completed:
            break
        }
    }

    /// 2枚目で項目を選んだ直後に、莉央の説明を開始する。
    func beginHabitSelectionIntroductionIfNeeded() {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .habitSelection,
              habitSelectionStage == .awaitingSelection,
              draft.selectedHabitID != nil else { return }
        habitSelectionStage = .firstMessage
    }

    func delayedGuidanceStage(for step: OnboardingSetupStep) -> OnboardingDelayedGuidanceStage? {
        switch step {
        case .goalSetting:
            return goalSettingGuidanceStage
        case .cueSelection:
            return cueSelectionGuidanceStage
        case .introduction, .habitSelection, .blockedBehaviorSelection, .confirmation:
            return nil
        }
    }

    /// 短い表示待機後も対象画面にいる場合、莉央の補足説明を表示する。
    func presentDelayedGuidanceIfNeeded(for step: OnboardingSetupStep) {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == step else { return }

        switch step {
        case .goalSetting:
            guard goalSettingGuidanceStage == .waitingToPresent else { return }
            goalSettingGuidanceStage = .presented
        case .cueSelection:
            guard cueSelectionGuidanceStage == .waitingToPresent else { return }
            cueSelectionGuidanceStage = .presented
        case .introduction, .habitSelection, .blockedBehaviorSelection, .confirmation:
            break
        }
    }

    /// 莉央のセリフから説明へ進み、説明後は元の選択画面へ戻す。
    func advanceDelayedGuidance(for step: OnboardingSetupStep) {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == step else { return }

        switch step {
        case .goalSetting:
            switch goalSettingGuidanceStage {
            case .presented:
                goalSettingGuidanceStage = .explanation
            case .explanation:
                goalSettingGuidanceStage = .completed
            case .waitingToPresent, .completed:
                break
            }
        case .cueSelection:
            switch cueSelectionGuidanceStage {
            case .presented:
                cueSelectionGuidanceStage = .explanation
            case .explanation:
                cueSelectionGuidanceStage = .completed
            case .waitingToPresent, .completed:
                break
            }
        case .introduction, .habitSelection, .blockedBehaviorSelection, .confirmation:
            break
        }
    }

    /// 説明からはセリフへ戻し、セリフからは案内を閉じて選択画面へ戻す。
    func retreatDelayedGuidance(for step: OnboardingSetupStep) {
        guard !isCompleted,
              phase == .dedicatedSetup,
              setupStep == step else { return }

        switch step {
        case .goalSetting:
            switch goalSettingGuidanceStage {
            case .explanation:
                goalSettingGuidanceStage = .presented
            case .presented:
                goalSettingGuidanceStage = .completed
            case .waitingToPresent, .completed:
                break
            }
        case .cueSelection:
            switch cueSelectionGuidanceStage {
            case .explanation:
                cueSelectionGuidanceStage = .presented
            case .presented:
                cueSelectionGuidanceStage = .completed
            case .waitingToPresent, .completed:
                break
            }
        case .introduction, .habitSelection, .blockedBehaviorSelection, .confirmation:
            break
        }
    }

    /// 1・2枚目では説明を1段階ずつ進め、それ以降は次の専用画面へ進む。
    /// 最終確認画面ではfalseを返す。
    @discardableResult
    func advanceSetup() -> Bool {
        guard !isCompleted,
              phase == .dedicatedSetup else {
            return false
        }

        if setupStep == .introduction {
            guard canContinue() else { return false }
            switch introductionStage {
            case .appIntroduction:
                introductionStage = .nameEntry
            case .nameEntry:
                introductionStage = .firstMessage
            case .firstMessage:
                introductionStage = .secondMessage
            case .secondMessage:
                introductionStage = .characterExplanation
            case .characterExplanation:
                performBatchUpdate {
                    habitSelectionStage = .awaitingSelection
                    setupStep = .habitSelection
                }
            }
            return true
        }

        if setupStep == .habitSelection {
            switch habitSelectionStage {
            case .awaitingSelection:
                guard draft.selectedHabitID != nil else { return false }
                habitSelectionStage = .firstMessage
            case .firstMessage:
                habitSelectionStage = .secondMessage
            case .secondMessage:
                habitSelectionStage = .systemExplanation
            case .systemExplanation:
                performBatchUpdate {
                    habitSelectionStage = .completed
                    if draft.hasHabitSelection {
                        setupStep = .goalSetting
                    }
                }
            case .completed:
                guard canContinue() else { return false }
                setupStep = .goalSetting
            }
            return true
        }

        if setupStep == .blockedBehaviorSelection {
            switch blockedBehaviorStage {
            case .waitingToPresent:
                return false
            case .firstMessage:
                blockedBehaviorStage = .secondMessage
            case .secondMessage:
                blockedBehaviorStage = .awaitingSelection
            case .awaitingSelection:
                guard draft.hasBlockedBehaviorSelection else { return false }
                if draft.blockedBehavior?.isNone == true {
                    performBatchUpdate {
                        blockedBehaviorStage = .completed
                        setupStep = .confirmation
                    }
                } else if draft.blockedBehavior?.usesScreenTime == true {
                    blockedBehaviorStage = .screenTimeConfiguration
                } else {
                    blockedBehaviorStage = .postSelectionFirstMessage
                }
            case .screenTimeConfiguration:
                guard draft.blockedBehavior?.hasValidScreenTimeConfiguration == true else {
                    return false
                }
                blockedBehaviorStage = .postSelectionFirstMessage
            case .postSelectionFirstMessage:
                blockedBehaviorStage = .postSelectionSecondMessage
            case .postSelectionSecondMessage:
                blockedBehaviorStage = .systemExplanation
            case .systemExplanation:
                performBatchUpdate {
                    blockedBehaviorStage = .completed
                    setupStep = .confirmation
                }
            case .completed:
                setupStep = .confirmation
            }
            return true
        }

        guard canContinue() else { return false }

        guard let index = OnboardingSetupStep.allCases.firstIndex(of: setupStep),
              OnboardingSetupStep.allCases.indices.contains(index + 1) else {
            return false
        }
        let nextStep = OnboardingSetupStep.allCases[index + 1]
        performBatchUpdate {
            if nextStep == .blockedBehaviorSelection,
               draft.blockedBehavior == nil,
               blockedBehaviorStage == .completed {
                // 追加前の最終確認データから内容を変更した場合は、新しい案内を初回表示する。
                blockedBehaviorStage = .waitingToPresent
            }
            setupStep = nextStep
        }
        return true
    }

    /// 前の段階・画面へ戻る。習慣選択画面からは名前を編集できる位置へ戻す。
    @discardableResult
    func retreatSetup() -> Bool {
        guard !isCompleted,
              phase == .dedicatedSetup else {
            return false
        }

        if setupStep == .introduction {
            switch introductionStage {
            case .appIntroduction:
                return false
            case .nameEntry:
                introductionStage = .appIntroduction
            case .firstMessage:
                introductionStage = .nameEntry
            case .secondMessage:
                introductionStage = .firstMessage
            case .characterExplanation:
                introductionStage = .secondMessage
            }
            return true
        }

        if setupStep == .habitSelection {
            switch habitSelectionStage {
            case .firstMessage:
                habitSelectionStage = .awaitingSelection
                return true
            case .secondMessage:
                habitSelectionStage = .firstMessage
                return true
            case .systemExplanation:
                habitSelectionStage = .secondMessage
                return true
            case .awaitingSelection, .completed:
                break
            }
        }

        if setupStep == .blockedBehaviorSelection {
            switch blockedBehaviorStage {
            case .firstMessage:
                blockedBehaviorStage = .awaitingSelection
                return true
            case .secondMessage:
                blockedBehaviorStage = .firstMessage
                return true
            case .postSelectionFirstMessage:
                blockedBehaviorStage = draft.blockedBehavior?.usesScreenTime == true
                    ? .screenTimeConfiguration
                    : .awaitingSelection
                return true
            case .postSelectionSecondMessage:
                blockedBehaviorStage = .postSelectionFirstMessage
                return true
            case .systemExplanation:
                blockedBehaviorStage = .postSelectionSecondMessage
                return true
            case .screenTimeConfiguration:
                blockedBehaviorStage = .awaitingSelection
                return true
            case .waitingToPresent, .awaitingSelection, .completed:
                break
            }
        }

        guard let index = OnboardingSetupStep.allCases.firstIndex(of: setupStep),
              index > OnboardingSetupStep.allCases.startIndex else {
            return false
        }
        performBatchUpdate {
            setupStep = OnboardingSetupStep.allCases[index - 1]
            if setupStep == .introduction {
                introductionStage = .nameEntry
                habitSelectionStage = .awaitingSelection
            } else if setupStep == .habitSelection {
                habitSelectionStage = .completed
            } else if setupStep == .blockedBehaviorSelection,
                      draft.blockedBehavior == nil {
                // 新画面追加前に最終確認まで進んでいた保存データは、戻っても行き止まりにしない。
                draft.blockedBehavior = OnboardingBlockedBehaviorDraft(
                    selectionID: OnboardingBlockedBehaviorDraft.noneID,
                    title: "",
                    iconName: nil
                )
                blockedBehaviorStage = .completed
            }
        }
        return true
    }

    /// 6枚目でRoutineの保存に成功した直後に呼び、プロローグへ移る。
    func beginInAppTutorial(createdRoutineID: UUID) {
        guard !isCompleted else { return }
        performBatchUpdate {
            self.createdRoutineID = createdRoutineID
            isPrologueAutoplayPending = true
            prologueMessageSecondLineShown = false
            tutorialReportShown = false
            tutorialReportCompleted = false
            phase = .prologue
        }
    }

    /// プロローグを最後まで再生（またはスキップ）した後、Home上の莉央の一言へ移る。
    func completePrologue() {
        guard !isCompleted, phase == .prologue else { return }
        performBatchUpdate {
            isPrologueAutoplayPending = false
            prologueMessageSecondLineShown = false
            phase = .prologueMessage
        }
    }

    /// 最初のセリフを見た後、莉央の位置を変えずに2つ目のセリフを追加する。
    func showSecondPrologueMessage() {
        guard !isCompleted,
              phase == .prologueMessage,
              !prologueMessageSecondLineShown else { return }
        prologueMessageSecondLineShown = true
    }

    /// 莉央の一言を確認した後、通常Home上の初回報告チュートリアルへ移る。
    func completePrologueMessage() {
        guard !isCompleted, phase == .prologueMessage else { return }
        phase = .firstReport
    }

    /// 旧バージョンですでにアプリを利用していたユーザーを移行する。
    /// 保存済みオンボーディングがある場合や、入力を始めた後には適用しない。
    func completeForExistingInstallationIfNeeded(hasExistingUserData: Bool) {
        guard hasExistingUserData,
              startedWithoutSavedState,
              !isCompleted,
              phase == .dedicatedSetup,
              setupStep == .introduction,
              draft == OnboardingDraft() else { return }

        performBatchUpdate {
            notificationChoice = .notNow
            tutorialReportShown = true
            tutorialReportCompleted = true
            isCompleted = true
            phase = .completed
        }
    }

    /// Coach Markが画面へ載った時点だけを記録する。途中終了時は次回も表示する。
    func markReportTutorialShown() {
        guard shouldPresentReportTutorial, !tutorialReportShown else { return }
        tutorialReportShown = true
    }

    /// Routine の保存とフェーズ保存の間でアプリが終了した場合の自己修復。
    /// 実データが達成済みなら、二重に達成ログを作らず次の案内へ進める。
    func reconcileFirstReportIfNeeded(isRoutineComplete: Bool) {
        guard isRoutineComplete,
              !isCompleted,
              phase == .firstReport else { return }
        completeFirstReport(with: .completed)
    }

    /// 達成時は会話案内へ進む。「あとで」は操作説明だけを終了し、達成を待つ。
    func completeFirstReport(with outcome: OnboardingFirstReportOutcome) {
        guard !isCompleted, phase == .firstReport else { return }
        performBatchUpdate {
            tutorialReportShown = true
            tutorialReportCompleted = true
            firstReportOutcome = outcome
            if outcome == .completed {
                phase = .conversationPrompt
            }
        }
    }

    /// 今日の会話を開始したか、あとで読むことにしたかを記録する。
    func completeConversationPrompt(with choice: OnboardingConversationChoice) {
        guard !isCompleted, phase == .conversationPrompt else { return }
        performBatchUpdate {
            conversationChoice = choice
            phase = .storyUnlockPresentation
        }
    }

    func recordConversationIdentity(_ identity: OnboardingConversationIdentity) {
        guard conversationIdentity == nil else { return }
        conversationIdentity = identity
    }

    /// 会話を最後まで読んだ時だけ呼ぶ。途中で閉じた場合は再開用に保持する。
    func clearConversationIdentity() {
        conversationIdentity = nil
    }

    /// 第一話を開く直前に保存し、アプリ終了後も再生待ちへ戻れるようにする。
    func beginFirstStoryPlayback() {
        guard !isCompleted, phase == .storyUnlockPresentation else { return }
        phase = .firstStoryPlayback
    }

    /// 読了前に閉じた場合は解禁案内へ戻し、同じ第一話から再開できるようにする。
    func pauseFirstStoryPlayback() {
        guard !isCompleted, phase == .firstStoryPlayback else { return }
        phase = .storyUnlockPresentation
    }

    /// 第一話の読了が永続化された後だけ、読了案内へ進める。
    func completeFirstStoryPlayback() {
        guard !isCompleted, phase == .firstStoryPlayback else { return }
        phase = .firstStoryReadConfirmation
    }

    func continueAfterFirstStoryRead() {
        guard !isCompleted, phase == .firstStoryReadConfirmation else { return }
        phase = .tomorrowPromise
    }

    /// 第一話が未解禁、または「あとで読む」を選んだ場合の導線。
    func completeStoryUnlockPresentation() {
        guard !isCompleted, phase == .storyUnlockPresentation else { return }
        phase = .tomorrowPromise
    }

    /// OS権限要求より前に呼び、通知設定の変更前状態と初回通知の下限を永続化する。
    /// 同じ処理の再試行では、ロールバック元だけは最初の値を維持する。
    func beginNotificationSetup(
        routineID: UUID,
        reminderMinuteOfDay: Int,
        notBefore: Date,
        originalScheduledStartMinute: Int?,
        originalNotificationsEnabled: Bool
    ) {
        guard !isCompleted, phase == .tomorrowPromise else { return }
        let normalizedMinute = min(max(reminderMinuteOfDay, 0), 24 * 60 - 1)
        let previous = pendingNotificationSetup?.routineID == routineID
            ? pendingNotificationSetup
            : nil
        let rollbackStartMinute: Int?
        let rollbackNotificationsEnabled: Bool
        if let previous {
            // Optionalのnilも「元は時刻未設定」という有効な復元値なので、そのまま維持する。
            rollbackStartMinute = previous.originalScheduledStartMinute
            rollbackNotificationsEnabled = previous.originalNotificationsEnabled
        } else {
            rollbackStartMinute = originalScheduledStartMinute
            rollbackNotificationsEnabled = originalNotificationsEnabled
        }

        performBatchUpdate {
            draft.setReminderMinuteOfDay(normalizedMinute)
            notificationRoutineID = routineID
            notificationNotBefore = notBefore
            pendingNotificationSetup = OnboardingNotificationSetup(
                routineID: routineID,
                reminderMinuteOfDay: normalizedMinute,
                notBefore: notBefore,
                originalScheduledStartMinute: rollbackStartMinute,
                originalNotificationsEnabled: rollbackNotificationsEnabled
            )
        }
    }

    /// 通知設定を取り消した後に、予約下限と途中状態を破棄する。
    func abandonNotificationSetup() {
        guard !isCompleted, phase == .tomorrowPromise else { return }
        performBatchUpdate {
            pendingNotificationSetup = nil
            notificationRoutineID = nil
            notificationNotBefore = nil
            draft.setReminderMinuteOfDay(nil)
        }
    }

    /// 通知の選択まで終え、次回起動からオンボーディングを表示しない状態にする。
    func completeOnboarding(
        notificationChoice: OnboardingNotificationChoice,
        reminderMinuteOfDay: Int? = nil
    ) {
        guard !isCompleted, phase == .tomorrowPromise else { return }
        performBatchUpdate {
            self.notificationChoice = notificationChoice
            draft.setReminderMinuteOfDay(reminderMinuteOfDay)
            pendingNotificationSetup = nil
            if notificationChoice == .notNow {
                notificationRoutineID = nil
                notificationNotBefore = nil
            }
            tutorialReportShown = true
            tutorialReportCompleted = true
            isCompleted = true
            phase = .completed
        }
    }

    /// 通知の選択を保存し、最後の莉央の一言を表示する。まだ完了扱いにはしない。
    func presentTomorrowRioMessage(
        notificationChoice: OnboardingNotificationChoice,
        reminderMinuteOfDay: Int? = nil
    ) {
        guard !isCompleted, phase == .tomorrowPromise else { return }
        performBatchUpdate {
            self.notificationChoice = notificationChoice
            draft.setReminderMinuteOfDay(reminderMinuteOfDay)
            pendingNotificationSetup = nil
            if notificationChoice == .notNow {
                notificationRoutineID = nil
                notificationNotBefore = nil
            }
            phase = .tomorrowRioMessage
        }
    }

    /// 莉央の一言を見終えたタイミングでオンボーディングを完了する。
    func completeTomorrowRioMessage() {
        guard !isCompleted,
              phase == .tomorrowRioMessage,
              notificationChoice != nil else { return }
        performBatchUpdate {
            tutorialReportShown = true
            tutorialReportCompleted = true
            isCompleted = true
            phase = .completed
        }
    }

    /// デバッグ・テスト・将来の「オンボーディングを再確認」に使える初期化。
    func reset() {
        let initial = Snapshot.initial
        performBatchUpdate {
            setupStep = initial.setupStep
            introductionStage = .appIntroduction
            habitSelectionStage = .awaitingSelection
            goalSettingGuidanceStage = .waitingToPresent
            cueSelectionGuidanceStage = .waitingToPresent
            blockedBehaviorStage = .waitingToPresent
            confirmationGuidanceStage = .waitingToPresent
            prologueMessageSecondLineShown = false
            phase = initial.phase
            draft = initial.draft
            createdRoutineID = nil
            firstReportOutcome = nil
            conversationChoice = nil
            conversationIdentity = nil
            notificationChoice = nil
            notificationRoutineID = nil
            notificationNotBefore = nil
            pendingNotificationSetup = nil
            isPrologueAutoplayPending = false
            tutorialReportShown = false
            tutorialReportCompleted = false
            isCompleted = false
        }
    }

    private func performBatchUpdate(_ update: () -> Void) {
        isBatchUpdating = true
        update()
        isBatchUpdating = false
        persist()
    }

    private func persistIfNeeded() {
        guard !isBatchUpdating else { return }
        persist()
    }

    private func persist() {
        let snapshot = Snapshot(
            version: Self.schemaVersion,
            setupStep: setupStep,
            introductionStage: introductionStage,
            habitSelectionStage: habitSelectionStage,
            goalSettingGuidanceStage: goalSettingGuidanceStage,
            cueSelectionGuidanceStage: cueSelectionGuidanceStage,
            blockedBehaviorStage: blockedBehaviorStage,
            confirmationGuidanceStage: confirmationGuidanceStage,
            prologueMessageSecondLineShown: prologueMessageSecondLineShown,
            phase: phase,
            draft: draft,
            createdRoutineID: createdRoutineID,
            firstReportOutcome: firstReportOutcome,
            conversationChoice: conversationChoice,
            conversationIdentity: conversationIdentity,
            notificationChoice: notificationChoice,
            notificationRoutineID: notificationRoutineID,
            notificationNotBefore: notificationNotBefore,
            pendingNotificationSetup: pendingNotificationSetup,
            isPrologueAutoplayPending: isPrologueAutoplayPending,
            tutorialReportShown: tutorialReportShown,
            tutorialReportCompleted: tutorialReportCompleted,
            isCompleted: isCompleted
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func loadSnapshot(
        defaults: UserDefaults,
        storageKey: String
    ) -> Snapshot? {
        guard let data = defaults.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == schemaVersion else {
            return nil
        }
        return snapshot
    }

    private static func restoredHabitSelectionStage(
        from snapshot: Snapshot
    ) -> OnboardingHabitSelectionStage {
        if snapshot.setupStep.orderIndex > OnboardingSetupStep.habitSelection.orderIndex {
            return .completed
        }
        if snapshot.setupStep == .habitSelection,
           snapshot.draft.selectedHabitID != nil {
            return .firstMessage
        }
        return .awaitingSelection
    }

    private static func restoredDelayedGuidanceStage(
        _ savedStage: OnboardingDelayedGuidanceStage?,
        for guidedStep: OnboardingSetupStep,
        setupStep: OnboardingSetupStep
    ) -> OnboardingDelayedGuidanceStage {
        if let savedStage {
            return savedStage
        }
        return setupStep.orderIndex > guidedStep.orderIndex ? .completed : .waitingToPresent
    }

    private static func restoredBlockedBehaviorStage(
        from snapshot: Snapshot
    ) -> OnboardingBlockedBehaviorStage {
        if snapshot.setupStep.orderIndex > OnboardingSetupStep.blockedBehaviorSelection.orderIndex {
            return .completed
        }
        if snapshot.setupStep == .blockedBehaviorSelection,
           snapshot.draft.hasBlockedBehaviorSelection {
            return .awaitingSelection
        }
        return .waitingToPresent
    }

    private static func restoredConfirmationGuidanceStage(
        from snapshot: Snapshot
    ) -> OnboardingConfirmationGuidanceStage {
        guard snapshot.phase == .dedicatedSetup, !snapshot.isCompleted else {
            return .completed
        }
        return .waitingToPresent
    }

    /// 通常の通知再計算からも、オンボーディングで指定した初回通知下限を参照する。
    static func persistedNotificationNotBefore(
        for routineID: UUID,
        defaults: UserDefaults = .standard,
        storageKey: String = OnboardingStateStore.defaultStorageKey
    ) -> Date? {
        guard let snapshot = loadSnapshot(defaults: defaults, storageKey: storageKey),
              snapshot.notificationRoutineID == routineID else { return nil }
        return snapshot.notificationNotBefore
    }

    private struct Snapshot: Codable {
        let version: Int
        var setupStep: OnboardingSetupStep
        // 追加前の保存データでも入力内容・後半の進行を復元できるようOptionalにする。
        var introductionStage: OnboardingIntroductionStage?
        // 追加前の保存データは画面位置と選択内容から安全な段階へ復元する。
        var habitSelectionStage: OnboardingHabitSelectionStage?
        // 追加前の保存データは画面位置から補完する。
        var goalSettingGuidanceStage: OnboardingDelayedGuidanceStage?
        var cueSelectionGuidanceStage: OnboardingDelayedGuidanceStage?
        var blockedBehaviorStage: OnboardingBlockedBehaviorStage?
        var confirmationGuidanceStage: OnboardingConfirmationGuidanceStage?
        var prologueMessageSecondLineShown: Bool?
        var phase: OnboardingPhase
        var draft: OnboardingDraft
        var createdRoutineID: UUID?
        var firstReportOutcome: OnboardingFirstReportOutcome?
        var conversationChoice: OnboardingConversationChoice?
        var conversationIdentity: OnboardingConversationIdentity?
        var notificationChoice: OnboardingNotificationChoice?
        var notificationRoutineID: UUID?
        var notificationNotBefore: Date?
        var pendingNotificationSetup: OnboardingNotificationSetup?
        // 追加前の完了済みユーザーへ突然プロローグを出さないよう、欠落時はfalseとして復元する。
        var isPrologueAutoplayPending: Bool?
        // 追加前の保存データはfirstReportOutcomeから安全に補完する。
        var tutorialReportShown: Bool?
        var tutorialReportCompleted: Bool?
        var isCompleted: Bool

        static let initial = Snapshot(
            version: OnboardingStateStore.schemaVersion,
            setupStep: .introduction,
            introductionStage: .appIntroduction,
            habitSelectionStage: .awaitingSelection,
            goalSettingGuidanceStage: .waitingToPresent,
            cueSelectionGuidanceStage: .waitingToPresent,
            blockedBehaviorStage: .waitingToPresent,
            confirmationGuidanceStage: .waitingToPresent,
            prologueMessageSecondLineShown: false,
            phase: .dedicatedSetup,
            draft: OnboardingDraft(),
            createdRoutineID: nil,
            firstReportOutcome: nil,
            conversationChoice: nil,
            conversationIdentity: nil,
            notificationChoice: nil,
            notificationRoutineID: nil,
            notificationNotBefore: nil,
            pendingNotificationSetup: nil,
            isPrologueAutoplayPending: false,
            tutorialReportShown: false,
            tutorialReportCompleted: false,
            isCompleted: false
        )
    }
}
