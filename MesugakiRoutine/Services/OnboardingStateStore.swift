import Foundation
import Observation

/// 専用オンボーディング画面（5画面）の現在位置。
enum OnboardingSetupStep: Int, Codable, CaseIterable, Sendable {
    case introduction
    case habitSelection
    case goalSetting
    case cueSelection
    case confirmation
}

/// 1枚目の名前入力から、莉央との出会いを段階的に表示する現在位置。
enum OnboardingIntroductionStage: String, Codable, Sendable {
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

/// 専用画面終了後を含む、オンボーディング全体の現在位置。
enum OnboardingPhase: String, Codable, Sendable {
    case dedicatedSetup
    case firstReport
    case conversationPrompt
    case storyUnlockPresentation
    case tomorrowPromise
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

/// 5画面で入力する内容。Routine を作成するまでは UserDefaults にだけ保持する。
struct OnboardingDraft: Codable, Equatable, Sendable {
    var userName: String

    /// プリセットまたは `custom` を識別する、UI側で安定したID。
    var selectedHabitID: String?
    /// 条件を付ける前の習慣名（例: 「本を読む」）。
    var habitTitle: String
    var habitIconName: String?

    /// 条件プリセットまたは `custom` を識別するID。
    var selectedGoalID: String?
    /// 画面表示用の達成条件（例: 「1ページ」）。
    var goalText: String
    /// Routine.title に保存する具体化済みタイトル（例: 「本を1ページ読む」）。
    var routineTitle: String

    /// タイミングプリセットまたは `custom` を識別するID。
    var selectedCueID: String?
    /// Routine.cueText に保存する実行タイミング（例: 「寝る前」）。
    var cueText: String

    /// 最終フェーズで選んだ通知時刻。0時からの分数（0...1439）。
    var reminderMinuteOfDay: Int?

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
        reminderMinuteOfDay: Int? = nil
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

    mutating func setReminderMinuteOfDay(_ minute: Int?) {
        reminderMinuteOfDay = minute.map(Self.normalizedMinuteOfDay)
    }

    private static func normalizedMinuteOfDay(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}

/// オンボーディングの入力内容と進行を、アプリ終了をまたいで復元するストア。
///
/// Routine の実データは5画面目で通常Repositoryへ保存し、このストアにはそのIDだけを保持する。
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
        phase = snapshot.phase
        draft = snapshot.draft
        createdRoutineID = snapshot.createdRoutineID
        firstReportOutcome = snapshot.firstReportOutcome
        conversationChoice = snapshot.conversationChoice
        conversationIdentity = snapshot.conversationIdentity
        notificationChoice = snapshot.notificationChoice
        notificationRoutineID = snapshot.notificationRoutineID
        notificationNotBefore = snapshot.notificationNotBefore
        pendingNotificationSetup = snapshot.pendingNotificationSetup

        // 完了状態とphaseの片方だけが保存された瞬間に終了しても、再起動時に完了を維持する。
        let restoredAsCompleted = snapshot.isCompleted || snapshot.phase == .completed
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

    func canContinue(from step: OnboardingSetupStep? = nil) -> Bool {
        switch step ?? setupStep {
        case .introduction:
            return draft.hasIdentity
        case .habitSelection:
            return draft.hasHabitSelection
        case .goalSetting:
            return draft.hasConcreteGoal && goalSettingGuidanceStage == .completed
        case .cueSelection:
            return draft.hasCueSelection && cueSelectionGuidanceStage == .completed
        case .confirmation:
            return draft.hasCueSelection
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
            }
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
        case .introduction, .habitSelection, .confirmation:
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
        case .introduction, .habitSelection, .confirmation:
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
        case .introduction, .habitSelection, .confirmation:
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
        case .introduction, .habitSelection, .confirmation:
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

        guard canContinue() else { return false }

        guard let index = OnboardingSetupStep.allCases.firstIndex(of: setupStep),
              OnboardingSetupStep.allCases.indices.contains(index + 1) else {
            return false
        }
        setupStep = OnboardingSetupStep.allCases[index + 1]
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
            case .nameEntry:
                return false
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
            }
        }
        return true
    }

    /// 5枚目でRoutineの保存に成功した直後に呼び、通常Home上のチュートリアルへ移る。
    func beginInAppTutorial(createdRoutineID: UUID) {
        guard !isCompleted else { return }
        performBatchUpdate {
            self.createdRoutineID = createdRoutineID
            phase = .firstReport
        }
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
            isCompleted = true
            phase = .completed
        }
    }

    /// Routine の保存とフェーズ保存の間でアプリが終了した場合の自己修復。
    /// 実データが達成済みなら、二重に達成ログを作らず次の案内へ進める。
    func reconcileFirstReportIfNeeded(isRoutineComplete: Bool) {
        guard isRoutineComplete,
              !isCompleted,
              phase == .firstReport else { return }
        completeFirstReport(with: .completed)
    }

    /// 通常の達成処理を実行したか、達成せず「あとで」を選んだかを記録する。
    func completeFirstReport(with outcome: OnboardingFirstReportOutcome) {
        guard !isCompleted, phase == .firstReport else { return }
        performBatchUpdate {
            firstReportOutcome = outcome
            phase = .conversationPrompt
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
            isCompleted = true
            phase = .completed
        }
    }

    /// デバッグ・テスト・将来の「オンボーディングを再確認」に使える初期化。
    func reset() {
        let initial = Snapshot.initial
        performBatchUpdate {
            setupStep = initial.setupStep
            introductionStage = .nameEntry
            habitSelectionStage = .awaitingSelection
            goalSettingGuidanceStage = .waitingToPresent
            cueSelectionGuidanceStage = .waitingToPresent
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
        if snapshot.setupStep.rawValue > OnboardingSetupStep.habitSelection.rawValue {
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
        return setupStep.rawValue > guidedStep.rawValue ? .completed : .waitingToPresent
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
        var isCompleted: Bool

        static let initial = Snapshot(
            version: OnboardingStateStore.schemaVersion,
            setupStep: .introduction,
            introductionStage: .nameEntry,
            habitSelectionStage: .awaitingSelection,
            goalSettingGuidanceStage: .waitingToPresent,
            cueSelectionGuidanceStage: .waitingToPresent,
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
            isCompleted: false
        )
    }
}
