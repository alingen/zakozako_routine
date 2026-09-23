import SwiftUI
import SwiftData

enum AppDialogActionStyle: Equatable {
    case standard
    case destructive
}

enum AppDialogActionResult {
    case dismiss
    case replace(AppDialogRequest)
    case showTaunt(BlockedBehaviorTauntRequest)
}

struct AppDialogAction: Identifiable {
    let id = UUID()
    let title: String
    let style: AppDialogActionStyle
    let action: () -> AppDialogActionResult

    init(
        _ title: String,
        style: AppDialogActionStyle = .standard,
        action: @escaping () -> AppDialogActionResult
    ) {
        self.title = title
        self.style = style
        self.action = action
    }
}

struct AppDialogRequest: Identifiable {
    let id = UUID()
    let title: String?
    let message: String?
    let actions: [AppDialogAction]
}

struct BlockedBehaviorTauntRequest: Identifiable {
    let id = UUID()
    let text: String
}

private enum RootTab: Hashable {
    case home
    case log
    case interaction
    case settings
}

/// アプリのルート画面。ホーム/記録/交流/設定をボトムタブで切り替える。
struct RootTabView: View {
    private static let prologueEventID = "event_prologue_001"
    private static let firstStoryEventID = "event_middle_001"

    @Environment(\.modelContext) private var modelContext
    @State private var appDialog: AppDialogRequest?
    @State private var blockedBehaviorTaunt: BlockedBehaviorTauntRequest?
    @State private var onboardingState = OnboardingStateStore()
    @State private var selectedTab: RootTab = .home
    @State private var openTodayConversationRequest = false
    @State private var openStoryEventRequest: String?
    @State private var isOnboardingConversationPlaying = false
    @State private var isOnboardingConversationDialog = false
    @State private var onboardingFirstStoryAvailable = false
    @State private var onboardingAlertTitle = "オンボーディングを完了できませんでした"
    @State private var onboardingErrorMessage: String?
    @State private var isSavingNotification = false
    @State private var onboardingReportTargetFrame: CGRect?
    @State private var onboardingReportActionTrigger = 0

    private var isPresentingOverlay: Bool {
        appDialog != nil
            || blockedBehaviorTaunt != nil
            || onboardingState.phase == .prologueMessage
            || onboardingState.phase == .storyUnlockPresentation
            || onboardingState.phase == .firstStoryReadConfirmation
    }

    private var isPresentingReportSpotlight: Bool {
        onboardingState.shouldPresentReportTutorial
    }

    var body: some View {
        ZStack {
            if onboardingState.shouldPresentDedicatedSetup {
                OnboardingSetupView(
                    stateStore: onboardingState,
                    onRequestScreenTimeAuthorization: {
                        let dependencies = AppDependencies(context: modelContext)
                        try await dependencies.screenTimeMonitoringService
                            .requestAuthorizationIfNeeded()
                    },
                    onConfirmPromise: saveFirstPromise
                )
                .transition(.opacity)
            } else {
                appShell

                if isPresentingReportSpotlight {
                    OnboardingFirstReportSpotlightView(
                        targetFrame: onboardingReportTargetFrame,
                        onReport: requestOnboardingReport,
                        onDefer: deferFirstReport
                    )
                    .transition(.opacity)
                    .zIndex(8)
                }

                if onboardingState.phase == .prologueMessage {
                    OnboardingPostPrologueMessageView(
                        routineTitle: onboardingRoutine()?.title
                            ?? onboardingState.draft.trimmedRoutineTitle,
                        showsSecondMessage: onboardingState.prologueMessageSecondLineShown,
                        onContinue: advancePostPrologueMessage
                    )
                    .transition(.opacity)
                    .zIndex(9)
                }

                if onboardingState.phase == .storyUnlockPresentation {
                    OnboardingStoryUnlockView(
                        didCompleteFirstPromise: onboardingState.firstReportOutcome == .completed,
                        hasUnlockedStory: onboardingFirstStoryAvailable,
                        onContinue: continueFromStoryUnlockPresentation,
                        onReadLater: onboardingState.completeStoryUnlockPresentation
                    )
                    .zIndex(10)
                }

                if onboardingState.phase == .firstStoryReadConfirmation {
                    OnboardingFirstStoryReadView(
                        onContinue: onboardingState.continueAfterFirstStoryRead
                    )
                    .zIndex(10)
                }

                if onboardingState.phase == .tomorrowPromise
                    || onboardingState.phase == .tomorrowRioMessage {
                    tomorrowPromiseView
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(20)
                        .allowsHitTesting(onboardingState.phase == .tomorrowPromise)
                        .accessibilityHidden(onboardingState.phase == .tomorrowRioMessage)
                }

                if onboardingState.phase == .tomorrowRioMessage {
                    OnboardingTomorrowRioMessageView(
                        onContinue: onboardingState.completeTomorrowRioMessage
                    )
                    .transition(.opacity)
                    .zIndex(21)
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isPresentingOverlay)
        .animation(.easeInOut(duration: 0.18), value: appDialog?.id)
        .animation(.easeOut(duration: 0.28), value: blockedBehaviorTaunt?.id)
        .animation(.easeInOut(duration: 0.24), value: onboardingState.phase)
        .animation(.easeInOut(duration: 0.2), value: isPresentingReportSpotlight)
        .task {
            resumeOnboardingIfNeeded()
        }
        .onChange(of: onboardingState.shouldPresentReportTutorial) { _, shouldPresent in
            if !shouldPresent {
                onboardingReportTargetFrame = nil
            }
        }
        .alert(
            onboardingAlertTitle,
            isPresented: Binding(
                get: { onboardingErrorMessage != nil },
                set: { if !$0 { dismissOnboardingAlert() } }
            )
        ) {
            Button("OK", action: dismissOnboardingAlert)
        } message: {
            Text(onboardingErrorMessage ?? "時間をおいて、もう一度お試しください。")
        }
        // 配色はライト前提の単一値パレットのため、ダーク時に破綻しないよう固定する。
        .preferredColorScheme(.light)
    }

    private var appShell: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    HomeView(
                        appDialog: $appDialog,
                        onboardingRoutineID: onboardingState.phase == .firstReport
                            ? onboardingState.createdRoutineID
                            : nil,
                        highlightsDeferredReport: onboardingState.firstReportOutcome == .deferred
                            && onboardingState.phase == .firstReport,
                        onboardingReportActionTrigger: onboardingReportActionTrigger,
                        onOnboardingRoutineCompleted: completeFirstReport,
                        onOnboardingReportTargetFrameChange: updateOnboardingReportTargetFrame
                    )
                }
                .tabItem {
                    Label("ホーム", systemImage: "house")
                }
                .tag(RootTab.home)

                NavigationStack {
                    RoutineLogView()
                }
                .tabItem {
                    Label("記録", systemImage: "list.bullet.clipboard")
                }
                .tag(RootTab.log)

                NavigationStack {
                    InteractionView(
                        openTodayConversationRequest: $openTodayConversationRequest,
                        openStoryEventRequest: $openStoryEventRequest,
                        onboardingConversationIdentity: onboardingState.conversationIdentity,
                        onOnboardingConversationPlaybackEnded: finishOnboardingConversation,
                        onOnboardingConversationUnavailable: finishUnavailableOnboardingConversation,
                        onStoryEventAutoPlayEnded: finishStoryEventAutoPlay
                    )
                }
                .tabItem {
                    Label("交流", systemImage: "sparkles")
                }
                .tag(RootTab.interaction)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("設定", systemImage: "gearshape")
                }
                .tag(RootTab.settings)
            }
            .tint(AppColor.primary)
            .allowsHitTesting(!isPresentingOverlay && !isPresentingReportSpotlight)
            .accessibilityHidden(isPresentingOverlay || isPresentingReportSpotlight)

            if isPresentingOverlay,
               onboardingState.phase != .storyUnlockPresentation,
               onboardingState.phase != .firstStoryReadConfirmation {
                Color.black.opacity(0.48)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: dismissPresentedOverlay)
                    .transition(.opacity)
                    .zIndex(1)
            }

            if let appDialog {
                appDialogCard(appDialog)
                    .id(appDialog.id)
                    .transition(.scale(scale: 0.98).combined(with: .opacity))
                    .zIndex(2)
            }

            if let blockedBehaviorTaunt {
                Button(action: dismissBlockedBehaviorTaunt) {
                    blockedBehaviorTauntOverlay(blockedBehaviorTaunt)
                }
                .buttonStyle(.plain)
                .id(blockedBehaviorTaunt.id)
                .transition(
                    .asymmetric(
                        insertion: .offset(y: 32)
                            .combined(with: .opacity),
                        removal: .opacity
                    )
                )
                .zIndex(3)
            }
        }
    }

    private var tomorrowPromiseView: some View {
        OnboardingTomorrowView(
            cueText: onboardingState.draft.trimmedCueText,
            routineTitle: onboardingState.draft.trimmedRoutineTitle,
            iconName: onboardingState.draft.habitIconName,
            initialReminderTime: initialReminderTime,
            isSaving: isSavingNotification,
            onEnableNotification: enableOnboardingNotification,
            onSkipNotification: skipOnboardingNotification
        )
    }

    private var initialReminderTime: Date {
        let minute = onboardingState.draft.reminderMinuteOfDay
            ?? suggestedStartMinute(for: onboardingState.draft.selectedCueID)
        return Routine.date(fromMinutes: minute)
    }

    private func saveFirstPromise() {
        guard onboardingState.phase == .dedicatedSetup,
              onboardingState.setupStep == .confirmation,
              onboardingState.canContinue(from: .confirmation) else { return }

        let draft = onboardingState.draft
        let dependencies = AppDependencies(context: modelContext)

        do {
            let blockedBehaviorToCreate = draft.blockedBehavior.flatMap { blockedBehavior in
                blockedBehavior.shouldCreate ? blockedBehavior : nil
            }
            let existingBlockedBehavior = blockedBehaviorToCreate.flatMap { blockedBehavior in
                let trackingKind: BlockedBehaviorTrackingKind = blockedBehavior.usesScreenTime
                    ? .screenTime
                    : .manual
                return dependencies.blockedBehaviorRepository.fetchAll().first {
                    $0.title == blockedBehavior.trimmedTitle
                        && $0.iconName == blockedBehavior.iconName
                        && $0.isActive
                        && $0.masteredAt == nil
                        && $0.limitPeriod == .day
                        && $0.effectiveLimit == 1
                        && $0.trackingKind == trackingKind
                        && (!blockedBehavior.usesScreenTime
                            || ($0.screenTimeLimitMinutes
                                == blockedBehavior.effectiveScreenTimeLimitMinutes
                                && $0.screenTimeSelectionData
                                    == blockedBehavior.screenTimeSelectionData))
                        && $0.usageEvents.isEmpty
                }
            }

            // 「やらないこと」は同時に1件だけ挑戦できる。Routineを作る前に確認し、部分保存を避ける。
            if blockedBehaviorToCreate != nil,
               existingBlockedBehavior == nil,
               !dependencies.blockedBehaviorRepository.canAddNew() {
                presentOnboardingError("すでに挑戦中の「やらないこと」があります。")
                return
            }

            // 保存直後にアプリが中断された場合も、同じ内容の約束を重複作成しない。
            let existing = dependencies.routineRepository.fetchAll().first {
                $0.title == draft.trimmedRoutineTitle
                    && $0.cueText == draft.trimmedCueText
                    && $0.iconName == draft.habitIconName
                    && $0.isActive
                    && $0.period == .day
                    && $0.targetCount == 1
                    && $0.scheduledStartMinute == nil
                    && $0.targetDurationMinutes == nil
                    && Set($0.activeWeekdayValues.isEmpty
                           ? Weekday.allWeekdayValues
                           : $0.activeWeekdayValues) == Set(Weekday.allWeekdayValues)
                    && $0.progressEvents.isEmpty
            }
            let routine = try existing ?? dependencies.routineRepository.create(
                title: draft.trimmedRoutineTitle,
                cueText: draft.trimmedCueText,
                iconName: draft.habitIconName,
                period: .day,
                targetCount: 1,
                scheduledStartMinute: nil,
                activeWeekdayValues: Weekday.allWeekdayValues,
                targetDurationMinutes: nil
            )

            if let blockedBehavior = blockedBehaviorToCreate {
                let trackingKind: BlockedBehaviorTrackingKind = blockedBehavior.usesScreenTime
                    ? .screenTime
                    : .manual
                var createdBlockedBehavior: BlockedBehavior?
                if existingBlockedBehavior == nil {
                    guard let created = dependencies.blockedBehaviorRepository.create(
                        title: blockedBehavior.trimmedTitle,
                        iconName: blockedBehavior.iconName,
                        limitPeriod: .day,
                        limitCount: 1,
                        trackingKind: trackingKind,
                        screenTimeLimitMinutes: blockedBehavior.usesScreenTime
                            ? blockedBehavior.effectiveScreenTimeLimitMinutes
                            : nil,
                        screenTimeSelectionData: blockedBehavior.usesScreenTime
                            ? blockedBehavior.screenTimeSelectionData
                            : nil
                    ) else {
                        if existing == nil {
                            try? dependencies.routineRepository.delete(routine)
                        }
                        presentOnboardingError("やめたい習慣を保存できませんでした。もう一度お試しください。")
                        return
                    }
                    createdBlockedBehavior = created
                }

                if blockedBehavior.usesScreenTime,
                   let savedBlockedBehavior = existingBlockedBehavior ?? createdBlockedBehavior {
                    do {
                        try dependencies.screenTimeMonitoringService
                            .ensureMonitoring(for: savedBlockedBehavior)
                    } catch {
                        if let createdBlockedBehavior {
                            _ = dependencies.blockedBehaviorRepository.delete(createdBlockedBehavior)
                        }
                        if existing == nil {
                            try? dependencies.routineRepository.delete(routine)
                        }
                        presentOnboardingError(error.localizedDescription)
                        return
                    }
                }
            }

            AppSettingsStore.userName = draft.trimmedUserName
            onboardingState.beginInAppTutorial(createdRoutineID: routine.id)
            presentPendingPrologueIfNeeded()
        } catch {
            presentOnboardingError("最初の約束を保存できませんでした。\n\(error.localizedDescription)")
        }
    }

    private func completeFirstReport() {
        guard onboardingState.phase == .firstReport else { return }
        onboardingReportTargetFrame = nil
        onboardingState.completeFirstReport(with: .completed)
        blockedBehaviorTaunt = BlockedBehaviorTauntRequest(text: "ざこなのに頑張ったね♡")
    }

    private func deferFirstReport() {
        guard onboardingState.phase == .firstReport else { return }
        // Routineの達成記録だけが先に保存されていた場合は、
        // 「あとでやる」で実際の達成結果を上書きせず成功として復旧する。
        if onboardingRoutine()?.isComplete() == true {
            completeFirstReport()
            return
        }
        onboardingState.completeFirstReport(with: .deferred)
    }

    private func requestOnboardingReport() {
        guard onboardingState.shouldPresentReportTutorial else { return }
        // Routineの記録だけが先に保存された直後にアプリが終了しても、
        // 再表示されたボタンで達成を取り消さない。
        if onboardingRoutine()?.isComplete() == true {
            completeFirstReport()
            return
        }
        onboardingReportActionTrigger &+= 1
    }

    private func updateOnboardingReportTargetFrame(_ frame: CGRect?) {
        guard onboardingState.shouldPresentReportTutorial else {
            if onboardingReportTargetFrame != nil {
                onboardingReportTargetFrame = nil
            }
            return
        }

        let validFrame = frame.flatMap { candidate in
            candidate.width > 0 && candidate.height > 0 ? candidate : nil
        }
        guard onboardingReportTargetFrame != validFrame else { return }

        onboardingReportTargetFrame = validFrame
        if validFrame != nil {
            onboardingState.markReportTutorialShown()
        }
    }

    private func presentConversationPromptIfNeeded() {
        guard onboardingState.phase == .conversationPrompt,
              !isOnboardingConversationPlaying,
              appDialog == nil,
              blockedBehaviorTaunt == nil else { return }

        isOnboardingConversationDialog = true
        appDialog = AppDialogRequest(
            title: "今日の会話をはじめる？",
            message: "莉央との最初の会話を楽しめます。あとから交流画面で読むこともできます。",
            actions: [
                AppDialogAction("あとで読む") {
                    isOnboardingConversationDialog = false
                    prepareOnboardingConversationIdentityIfNeeded()
                    onboardingState.completeConversationPrompt(with: .later)
                    prepareStoryUnlockPresentation()
                    return .dismiss
                },
                AppDialogAction("はじめる") {
                    isOnboardingConversationDialog = false
                    prepareOnboardingConversationIdentityIfNeeded()
                    isOnboardingConversationPlaying = true
                    selectedTab = .interaction
                    openTodayConversationRequest = true
                    return .dismiss
                },
            ]
        )
    }

    private func finishOnboardingConversation(didComplete: Bool) {
        if didComplete {
            onboardingState.clearConversationIdentity()
        }

        guard isOnboardingConversationPlaying,
              onboardingState.phase == .conversationPrompt else { return }
        isOnboardingConversationPlaying = false
        onboardingState.completeConversationPrompt(with: .started)
        prepareStoryUnlockPresentation()
    }

    private func finishUnavailableOnboardingConversation() {
        guard isOnboardingConversationPlaying else { return }
        finishOnboardingConversation(didComplete: false)
    }

    @discardableResult
    private func prepareOnboardingConversationIdentityIfNeeded(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> OnboardingConversationIdentity? {
        if let identity = onboardingState.conversationIdentity {
            return identity
        }

        let dependencies = AppDependencies(context: modelContext)
        guard let content = dependencies.storyContentRepository,
              let launch = InteractionViewModel.onboardingConversationLaunch(
                now: now,
                calendar: calendar,
                dailyScenarios: content.dailyScenarios,
                checkpointForPlaybackKey: {
                    try? dependencies.storyStateRepository.checkpoint(for: $0)
                }
              ) else {
            return nil
        }

        let identity = InteractionViewModel.onboardingConversationIdentity(for: launch)
        onboardingState.recordConversationIdentity(identity)
        return identity
    }

    private func prepareStoryUnlockPresentation() {
        guard onboardingState.phase == .storyUnlockPresentation else { return }

        let dependencies = AppDependencies(context: modelContext)
        do {
            let refresh = try dependencies.storyUnlockService?.refreshUnlocks()
            onboardingFirstStoryAvailable = refresh?.events.first(where: {
                $0.event.eventId == Self.firstStoryEventID
            })?.canPlay == true
        } catch {
            // 未確認の状態を「第一話が解禁された」とは表示しない。
            onboardingFirstStoryAvailable = false
        }
    }

    private func continueFromStoryUnlockPresentation() {
        guard onboardingState.phase == .storyUnlockPresentation else { return }
        if !onboardingFirstStoryAvailable {
            prepareStoryUnlockPresentation()
        }
        guard onboardingFirstStoryAvailable else {
            if onboardingState.firstReportOutcome == .deferred {
                // 「あとでやる」だけでは第一話を強制解禁しない。
                onboardingState.completeStoryUnlockPresentation()
            } else {
                presentOnboardingError("第一話の解禁状態を確認できませんでした。もう一度お試しください。")
            }
            return
        }

        onboardingState.beginFirstStoryPlayback()
        presentPendingFirstStoryIfNeeded()
    }

    private var isFirstStoryRead: Bool {
        let dependencies = AppDependencies(context: modelContext)
        let progress = try? dependencies.storyStateRepository.eventProgress(
            for: Self.firstStoryEventID
        )
        if progress?.isRead == true { return true }
        return (try? dependencies.storyStateRepository.checkpoint(
            for: "event:\(Self.firstStoryEventID)"
        ))?.isCompleted == true
    }

    private var hasOpenedFirstStory: Bool {
        let progress = try? AppDependencies(context: modelContext)
            .storyStateRepository
            .eventProgress(for: Self.firstStoryEventID)
        return progress?.firstOpenedAt != nil
    }

    private func presentPendingFirstStoryIfNeeded() {
        guard onboardingState.phase == .firstStoryPlayback,
              openStoryEventRequest == nil else { return }

        // 読了保存と画面終了通知の間で終了しても、第一話を二重再生しない。
        if isFirstStoryRead {
            selectedTab = .interaction
            onboardingState.completeFirstStoryPlayback()
            return
        }

        let dependencies = AppDependencies(context: modelContext)
        do {
            let refresh = try dependencies.storyUnlockService?.refreshUnlocks()
            guard refresh?.events.first(where: {
                $0.event.eventId == Self.firstStoryEventID
            })?.canPlay == true else {
                handleUnavailableFirstStory(
                    "第一話を開けませんでした。時間をおいて、もう一度お試しください。"
                )
                return
            }
        } catch {
            handleUnavailableFirstStory("第一話を開けませんでした。\n\(error.localizedDescription)")
            return
        }

        selectedTab = .interaction
        openStoryEventRequest = Self.firstStoryEventID
    }

    private func handleUnavailableFirstStory(_ message: String) {
        if hasOpenedFirstStory {
            onboardingState.leaveFirstStoryPlayback()
        } else {
            onboardingState.pauseFirstStoryPlayback()
            prepareStoryUnlockPresentation()
            presentOnboardingError(message)
        }
    }

    private func enableOnboardingNotification(at time: Date) {
        guard onboardingState.phase == .tomorrowPromise,
              !isSavingNotification else { return }
        guard let routine = onboardingRoutine() else {
            presentOnboardingError("最初の約束が見つかりませんでした。")
            return
        }

        let minute = Routine.minutes(from: time)
        let calendar = Calendar.current
        let startOfTomorrow = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: .now)
        ) ?? .now

        // 権限ダイアログ中にアプリが終了しても、次回起動時に予約を戻せるよう先に保存する。
        onboardingState.beginNotificationSetup(
            routineID: routine.id,
            reminderMinuteOfDay: minute,
            notBefore: startOfTomorrow,
            originalScheduledStartMinute: routine.scheduledStartMinute,
            originalNotificationsEnabled: AppSettingsStore.notificationsEnabled
        )

        isSavingNotification = true
        Task { @MainActor in
            defer { isSavingNotification = false }
            let dependencies = AppDependencies(context: modelContext)
            await dependencies.notificationScheduler.requestAuthorizationIfNeeded()
            guard await dependencies.notificationScheduler.isAuthorized else {
                await finishWithoutOnboardingNotification(
                    message: "通知が許可されなかったため、通知なしで開始しました。通知は設定画面からいつでも有効にできます。"
                )
                return
            }

            do {
                try dependencies.routineRepository.update(
                    routine,
                    title: routine.title,
                    cueText: routine.cueText,
                    isActive: routine.isActive,
                    iconName: routine.iconName,
                    period: routine.period,
                    targetCount: routine.targetCount,
                    scheduledStartMinute: minute,
                    activeWeekdayValues: routine.activeWeekdayValues,
                    targetDurationMinutes: routine.targetDurationMinutes
                )
                AppSettingsStore.notificationsEnabled = true
                await dependencies.notificationScheduler.reschedule(
                    routines: [routine],
                    calendar: calendar,
                    notBefore: startOfTomorrow
                )
                onboardingState.presentTomorrowRioMessage(
                    notificationChoice: .enabled,
                    reminderMinuteOfDay: minute
                )
            } catch {
                presentOnboardingError("通知設定を保存できませんでした。\n\(error.localizedDescription)")
            }
        }
    }

    private func skipOnboardingNotification() {
        guard onboardingState.phase == .tomorrowPromise,
              !isSavingNotification else { return }
        isSavingNotification = true
        Task { @MainActor in
            defer { isSavingNotification = false }
            await finishWithoutOnboardingNotification()
        }
    }

    /// 中断された通知設定を変更前へ戻し、オンボーディング由来の予約を消す。
    private func finishWithoutOnboardingNotification(message: String? = nil) async {
        let dependencies = AppDependencies(context: modelContext)

        if let pending = onboardingState.pendingNotificationSetup {
            dependencies.notificationScheduler.cancelNotification(for: pending.routineID)

            if let routine = dependencies.routineRepository.fetchAll().first(where: {
                $0.id == pending.routineID
            }) {
                do {
                    try dependencies.routineRepository.update(
                        routine,
                        title: routine.title,
                        cueText: routine.cueText,
                        isActive: routine.isActive,
                        iconName: routine.iconName,
                        period: routine.period,
                        targetCount: routine.targetCount,
                        scheduledStartMinute: pending.originalScheduledStartMinute,
                        activeWeekdayValues: routine.activeWeekdayValues,
                        targetDurationMinutes: routine.targetDurationMinutes
                    )
                } catch {
                    presentOnboardingError("通知設定を元に戻せませんでした。\n\(error.localizedDescription)")
                    return
                }
            }

            AppSettingsStore.notificationsEnabled = pending.originalNotificationsEnabled
            onboardingState.abandonNotificationSetup()

            // もともと通知が有効だった場合は、変更前のRoutine状態で予約を作り直す。
            if pending.originalNotificationsEnabled {
                let routines = dependencies.routineRepository.fetchAll().filter { $0.isActive }
                await dependencies.notificationScheduler.reschedule(routines: routines)
            }
        }

        onboardingState.presentTomorrowRioMessage(notificationChoice: .notNow)
        if let message {
            onboardingAlertTitle = "通知は設定されませんでした"
            onboardingErrorMessage = message
        }
    }

    private func presentOnboardingError(_ message: String) {
        onboardingAlertTitle = "オンボーディングを完了できませんでした"
        onboardingErrorMessage = message
    }

    private func dismissOnboardingAlert() {
        onboardingErrorMessage = nil
        onboardingAlertTitle = "オンボーディングを完了できませんでした"
        if onboardingState.phase == .prologue {
            Task { @MainActor in
                await Task.yield()
                presentPendingPrologueIfNeeded()
            }
        }
    }

    private func onboardingRoutine() -> Routine? {
        guard let id = onboardingState.createdRoutineID else { return nil }
        return AppDependencies(context: modelContext)
            .routineRepository
            .fetchAll()
            .first { $0.id == id }
    }

    private func resumeOnboardingIfNeeded() {
        migrateExistingInstallationIfNeeded()
        clearCompletedOnboardingConversationIdentityIfNeeded()
        guard !onboardingState.isCompleted else { return }

        if onboardingState.phase != .dedicatedSetup,
           onboardingRoutine() == nil {
            onboardingState.goToSetupStep(.confirmation)
            return
        }

        switch onboardingState.phase {
        case .dedicatedSetup:
            break
        case .prologue:
            presentPendingPrologueIfNeeded()
        case .prologueMessage:
            selectedTab = .home
        case .firstReport:
            selectedTab = .home
            if let routine = onboardingRoutine(), routine.isComplete() {
                onboardingState.reconcileFirstReportIfNeeded(isRoutineComplete: true)
                blockedBehaviorTaunt = BlockedBehaviorTauntRequest(
                    text: "ざこなのに頑張ったね♡"
                )
            }
        case .conversationPrompt:
            presentConversationPromptIfNeeded()
        case .storyUnlockPresentation:
            prepareStoryUnlockPresentation()
        case .firstStoryPlayback:
            presentPendingFirstStoryIfNeeded()
        case .firstStoryReadConfirmation:
            selectedTab = .interaction
        case .tomorrowPromise, .tomorrowRioMessage, .completed:
            break
        }
    }

    private func presentPendingPrologueIfNeeded() {
        guard onboardingState.phase == .prologue,
              onboardingState.isPrologueAutoplayPending,
              openStoryEventRequest == nil else { return }

        // 読了保存と画面終了通知の間でアプリが終了した場合は、再生を要求し直さず
        // Home上の案内から安全に再開する。
        if isProloguePlaybackCompleted {
            selectedTab = .home
            onboardingState.completePrologue()
            return
        }

        selectedTab = .interaction
        openStoryEventRequest = Self.prologueEventID
    }

    private var isProloguePlaybackCompleted: Bool {
        let playbackKey = "event:\(Self.prologueEventID)"
        return (try? AppDependencies(context: modelContext)
            .storyStateRepository
            .checkpoint(for: playbackKey))?.isCompleted == true
    }

    private func finishStoryEventAutoPlay(eventID: String, didComplete: Bool) {
        switch eventID {
        case Self.prologueEventID where onboardingState.phase == .prologue:
            guard didComplete else {
                presentOnboardingError("プロローグが完了していません。もう一度お試しください。")
                return
            }
            selectedTab = .home
            onboardingState.completePrologue()

        case Self.firstStoryEventID where onboardingState.phase == .firstStoryPlayback:
            if didComplete || isFirstStoryRead {
                onboardingState.completeFirstStoryPlayback()
            } else if hasOpenedFirstStory {
                onboardingState.leaveFirstStoryPlayback()
            } else {
                handleUnavailableFirstStory(
                    "第一話を開けませんでした。時間をおいて、もう一度お試しください。"
                )
            }

        default:
            break
        }
    }

    private func advancePostPrologueMessage() {
        guard onboardingState.phase == .prologueMessage else { return }
        guard onboardingState.prologueMessageSecondLineShown else {
            onboardingState.showSecondPrologueMessage()
            return
        }
        selectedTab = .home
        onboardingState.completePrologueMessage()
    }

    /// オンボーディング導入前からデータがある端末は、既存ユーザーとして通常画面を維持する。
    private func migrateExistingInstallationIfNeeded() {
        guard onboardingState.startedWithoutSavedState else { return }

        let dependencies = AppDependencies(context: modelContext)
        let hasStoryState = (try? dependencies.storyStateRepository.eventProgresses().isEmpty) == false
        let hasExistingUserData = !dependencies.routineRepository.fetchAll().isEmpty
            || !dependencies.blockedBehaviorRepository.fetchAll().isEmpty
            || hasStoryState
            || !AppSettingsStore.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        onboardingState.completeForExistingInstallationIfNeeded(
            hasExistingUserData: hasExistingUserData
        )
    }

    private func clearCompletedOnboardingConversationIdentityIfNeeded() {
        guard let identity = onboardingState.conversationIdentity else { return }
        let checkpoint = try? AppDependencies(context: modelContext)
            .storyStateRepository
            .checkpoint(for: identity.playbackKey)
        if checkpoint?.isCompleted == true {
            onboardingState.clearConversationIdentity()
        }
    }

    private func suggestedStartMinute(for cueID: String?) -> Int {
        switch cueID {
        case "after-waking": return 7 * 60
        case "after-breakfast": return 8 * 60
        case "after-lunch": return 12 * 60 + 30
        case "after-arriving-home": return 19 * 60
        case "after-bath": return 21 * 60 + 30
        case "after-brushing": return 22 * 60
        case "before-sleep": return 22 * 60 + 30
        default: return 20 * 60
        }
    }

    private func appDialogCard(_ request: AppDialogRequest) -> some View {
        ZStack {
            Color.clear
                .allowsHitTesting(false)

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    if let title = request.title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(AppColor.text)
                    }

                    if let message = request.message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(AppColor.muted)
                            .multilineTextAlignment(.center)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        dialogButtons(for: request)
                    }

                    VStack(spacing: 12) {
                        dialogButtons(for: request)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 420)
            .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 32)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) {
                if !isOnboardingConversationDialog {
                    appDialog = nil
                }
            }
        }
    }

    @ViewBuilder
    private func dialogButtons(for request: AppDialogRequest) -> some View {
        ForEach(request.actions) { action in
            Button(role: action.style == .destructive ? .destructive : nil) {
                handle(action.action())
            } label: {
                Text(action.title)
                    .font(.headline)
                    .foregroundStyle(action.style == .destructive ? Color.white : AppColor.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        action.style == .destructive ? AppColor.error : AppColor.background,
                        in: Capsule()
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private func handle(_ result: AppDialogActionResult) {
        switch result {
        case .dismiss:
            appDialog = nil
        case let .replace(request):
            appDialog = request
        case let .showTaunt(request):
            appDialog = nil
            blockedBehaviorTaunt = request
        }
    }

    private func blockedBehaviorTauntOverlay(_ request: BlockedBehaviorTauntRequest) -> some View {
        GeometryReader { _ in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())

                RioSpeechRow {
                    OnboardingRioBubble(text: request.text)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("莉央、\(request.text)")
        .accessibilityHint("タップして閉じる")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.escape, dismissBlockedBehaviorTaunt)
    }

    private func dismissBlockedBehaviorTaunt() {
        blockedBehaviorTaunt = nil
        if onboardingState.phase == .conversationPrompt {
            Task { @MainActor in
                await Task.yield()
                presentConversationPromptIfNeeded()
            }
        }
    }

    private func dismissPresentedOverlay() {
        if isOnboardingConversationDialog { return }
        if onboardingState.phase == .prologueMessage {
            advancePostPrologueMessage()
        } else if blockedBehaviorTaunt != nil {
            dismissBlockedBehaviorTaunt()
        } else {
            appDialog = nil
        }
    }
}

/// 通常のHomeレイアウトを動かさず、最初の達成報告先だけを案内するCoach Mark。
private struct OnboardingFirstReportSpotlightView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let targetFrame: CGRect?
    let onReport: () -> Void
    let onDefer: () -> Void

    @State private var isPulseExpanded = false
    @State private var isSubmitting = false
    @State private var reportCalloutSize: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let overlayFrame = proxy.frame(in: .global)
            let localizedTarget = targetFrame.map { target in
                CGRect(
                    x: target.minX - overlayFrame.minX,
                    y: target.minY - overlayFrame.minY,
                    width: target.width,
                    height: target.height
                )
            }
            let visibleTarget = localizedTarget.flatMap { target in
                target.intersects(CGRect(origin: .zero, size: proxy.size)) ? target : nil
            }
            let spotlightRect = visibleTarget.map {
                $0.insetBy(dx: -9, dy: -9)
            }

            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)

                OnboardingSpotlightMask(targetRect: spotlightRect)
                    .fill(
                        Color.black.opacity(0.56),
                        style: FillStyle(eoFill: true)
                    )
                    .allowsHitTesting(false)

                if let target = visibleTarget {
                    spotlightRing(for: target)
                    reportButton(for: target)
                    reportCallout(
                        for: target,
                        in: proxy.size,
                        safeAreaInsets: proxy.safeAreaInsets
                    )
                }

                VStack(spacing: 10) {
                    Spacer(minLength: 0)

                    Text("まだできていない？")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Button(action: deferTutorial) {
                        Text("あとでやる")
                            .font(.headline)
                            .foregroundStyle(AppColor.primary)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(AppColor.surface, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSubmitting)
                    .frame(maxWidth: 260)
                    .accessibilityHint("達成を記録せず、操作説明を終了します")
                }
                .padding(.horizontal, 24)
                .padding(.bottom, max(74, proxy.safeAreaInsets.bottom + 56))
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .onPreferenceChange(OnboardingReportCalloutSizePreferenceKey.self) { size in
                guard size.width > 0, size.height > 0, reportCalloutSize != size else { return }
                reportCalloutSize = size
            }
        }
        .ignoresSafeArea()
        .onAppear(perform: startPulseAnimation)
        .onChange(of: reduceMotion) { _, _ in
            startPulseAnimation()
        }
        .accessibilityAddTraits(.isModal)
    }

    private func spotlightRing(for target: CGRect) -> some View {
        let diameter = max(target.width, target.height) + 18

        return Circle()
            .stroke(AppColor.primary, lineWidth: 3)
            .frame(width: diameter, height: diameter)
            .scaleEffect(reduceMotion ? 1 : (isPulseExpanded ? 1.13 : 0.96))
            .opacity(reduceMotion ? 1 : (isPulseExpanded ? 0.38 : 1))
            .position(x: target.midX, y: target.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func reportButton(for target: CGRect) -> some View {
        Button(action: requestReport) {
            Circle()
                .fill(Color.white.opacity(0.001))
                .frame(width: target.width, height: target.height)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
        .contentShape(Circle())
        .position(x: target.midX, y: target.midY)
        .accessibilityLabel("最初の約束を報告")
        .accessibilityHint("実行できたらタップして達成を記録します")
    }

    private func reportCallout(
        for target: CGRect,
        in size: CGSize,
        safeAreaInsets: EdgeInsets
    ) -> some View {
        let width = min(310, max(220, size.width - 40))
        let horizontalMargin: CGFloat = 16
        let preferredCenterX = target.midX - width * 0.28
        let centerX = min(
            max(preferredCenterX, horizontalMargin + width / 2),
            size.width - horizontalMargin - width / 2
        )
        let calloutHeight = reportCalloutSize.height > 0 ? reportCalloutSize.height : 74
        let bottomPadding = max(74, safeAreaInsets.bottom + 56)
        let bottomControlsTop = size.height - bottomPadding - 84
        let safeTop = max(16, safeAreaInsets.top + 12)
        let shouldPlaceBelow = target.maxY + calloutHeight + 30 < bottomControlsTop
        let desiredCenterY = shouldPlaceBelow
            ? target.maxY + calloutHeight / 2 + 18
            : target.minY - calloutHeight / 2 - 18
        let minimumCenterY = safeTop + calloutHeight / 2
        let maximumCenterY = max(
            minimumCenterY,
            bottomControlsTop - calloutHeight / 2 - 12
        )
        let centerY = min(max(desiredCenterY, minimumCenterY), maximumCenterY)

        return VStack(alignment: .trailing, spacing: 5) {
            if shouldPlaceBelow {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.primary)
                    .padding(.trailing, 16)
            }

            Text("実行できたら、ここをタップして報告")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.text)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 13)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppColor.primary.opacity(0.45), lineWidth: 1)
                }
                .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)

            if !shouldPlaceBelow {
                Image(systemName: "arrow.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppColor.primary)
                    .padding(.trailing, 16)
            }
        }
        .frame(width: width)
        .background {
            GeometryReader { calloutProxy in
                Color.clear.preference(
                    key: OnboardingReportCalloutSizePreferenceKey.self,
                    value: calloutProxy.size
                )
            }
        }
        .position(x: centerX, y: centerY)
        .allowsHitTesting(false)
    }

    private func startPulseAnimation() {
        isPulseExpanded = false
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: true)) {
            isPulseExpanded = true
        }
    }

    private func requestReport() {
        guard !isSubmitting else { return }
        isSubmitting = true
        onReport()
        releaseSubmissionLockIfStillPresented()
    }

    private func deferTutorial() {
        guard !isSubmitting else { return }
        isSubmitting = true
        onDefer()
    }

    private func releaseSubmissionLockIfStillPresented() {
        Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(900))
            } catch {
                return
            }
            isSubmitting = false
        }
    }
}

private struct OnboardingSpotlightMask: Shape {
    let targetRect: CGRect?

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        if let targetRect {
            path.addEllipse(in: targetRect)
        }
        return path
    }
}

private struct OnboardingReportCalloutSizePreferenceKey: PreferenceKey {
    static var defaultValue = CGSize.zero

    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next.width > 0, next.height > 0 {
            value = next
        }
    }
}

/// プロローグ直後、初回報告へ移る前にHome上へ重ねる莉央の一言。
private struct OnboardingPostPrologueMessageView: View {
    let routineTitle: String
    let showsSecondMessage: Bool
    let onContinue: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var todayMessage: String {
        "今日は「\(routineTitle)」だよ"
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 22) {
                    RioSpeechRow {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 10) {
                                OnboardingRioBubble(text: todayMessage)

                                if showsSecondMessage {
                                    OnboardingRioBubble(text: "できたら報告してね〜")
                                        .transition(
                                            reduceMotion
                                                ? .opacity
                                                : .offset(y: 8).combined(with: .opacity)
                                        )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    }
                    .frame(
                        maxWidth: 520,
                        minHeight: dynamicTypeSize.isAccessibilitySize ? 210 : 150,
                        maxHeight: dynamicTypeSize.isAccessibilitySize ? 210 : 150,
                        alignment: .top
                    )
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onContinue)

                    Button("次へ", action: onContinue)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppColor.text)
                        .padding(.horizontal, 20)
                        .frame(minHeight: 44)
                        .background(AppColor.surface.opacity(0.95), in: Capsule())
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("onboarding.prologueMessage.continue")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .center)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(.easeOut(duration: reduceMotion ? 0.1 : 0.22), value: showsSecondMessage)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            showsSecondMessage
                ? "莉央、\(todayMessage)。できたら報告してね〜"
                : "莉央、\(todayMessage)"
        )
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onContinue)
    }
}

#Preview {
    RootTabView()
        .environment(SiriLaunchCoordinator())
        .modelContainer(
            for: [
                Routine.self,
                BlockedBehavior.self,
                StoryEventProgress.self,
                StoryPlaybackProgress.self,
                StoryProfileValue.self,
                StoryMemoryUnlock.self,
            ],
            inMemory: true
        )
}
