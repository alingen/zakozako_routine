import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = HomeViewModel()
    @State private var editingRoutine: Routine?
    @State private var editingBlockedBehavior: BlockedBehavior?
    @State private var activeTimer: ActiveRoutineTimer?
    @State private var presentedTimer: ActiveRoutineTimer?
    @State private var pendingTimerCompletion: PendingTimerCompletion?
    @State private var timerDialogID: UUID?
    @State private var backgroundTimerCompletionFeedbackTrigger = 0
    @State private var isPresentingNewRoutine = false
    @State private var isPresentingNewBlockedBehavior = false
    @State private var isShowingBlockedBehaviorDeleteError = false
    @State private var nextStrugglingTauntIndex = 0
    @State private var nextDefeatedTauntIndex = 0
    @State private var rioReaction: RioReaction?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Binding private var appDialog: AppDialogRequest?
    private let onboardingRoutineID: UUID?
    private let highlightsDeferredReport: Bool
    private let onboardingReportActionTrigger: Int
    private let onOnboardingRoutineCompleted: () -> Void
    private let onOnboardingReportTargetFrameChange: (CGRect?) -> Void

    init(
        appDialog: Binding<AppDialogRequest?> = .constant(nil),
        onboardingRoutineID: UUID? = nil,
        highlightsDeferredReport: Bool = false,
        onboardingReportActionTrigger: Int = 0,
        onOnboardingRoutineCompleted: @escaping () -> Void = {},
        onOnboardingReportTargetFrameChange: @escaping (CGRect?) -> Void = { _ in }
    ) {
        _appDialog = appDialog
        self.onboardingRoutineID = onboardingRoutineID
        self.highlightsDeferredReport = highlightsDeferredReport
        self.onboardingReportActionTrigger = onboardingReportActionTrigger
        self.onOnboardingRoutineCompleted = onOnboardingRoutineCompleted
        self.onOnboardingReportTargetFrameChange = onOnboardingReportTargetFrameChange
    }

    private var hiddenTimerWatcherID: UUID? {
        guard let activeTimer,
              scenePhase == .active,
              presentedTimer == nil,
              activeTimer.session.phase == .running else { return nil }
        return activeTimer.id
    }

    var body: some View {
        List {
            rioHeaderSection
            todayRoutinesSection
            todayPromiseSection
            zakoBulletinSection
        }
        .appScreenBackground()
        .overlay(alignment: .bottom) {
            if let rioReaction {
                Button {
                    dismissRioReaction()
                } label: {
                    RioReactionToast(reaction: rioReaction)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
                .id(rioReaction.id)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .bottom).combined(with: .opacity)
                )
            }
        }
        // 画面をふさがない一言なので、数秒で自動的に下げる。
        .task(id: rioReaction?.id) {
            guard let id = rioReaction?.id else { return }
            do {
                try await Task.sleep(for: .seconds(3))
            } catch {
                return
            }
            if rioReaction?.id == id {
                dismissRioReaction()
            }
        }
        .navigationDestination(item: $editingRoutine) { routine in
            RoutineEditView(routine: routine)
        }
        .navigationDestination(item: $editingBlockedBehavior) { behavior in
            blockedBehaviorEditor(for: behavior)
        }
        .onChange(of: editingRoutine) { _, new in
            if new == nil { viewModel.reload() }
        }
        .onChange(of: editingBlockedBehavior) { _, new in
            if new == nil { viewModel.reload() }
        }
        .sheet(isPresented: $isPresentingNewRoutine, onDismiss: { viewModel.reload() }) {
            NavigationStack {
                RoutineEditView(routine: nil)
            }
        }
        .sheet(isPresented: $isPresentingNewBlockedBehavior, onDismiss: { viewModel.reload() }) {
            NavigationStack {
                BlockedBehaviorCreateView(
                    onRequestScreenTimeAuthorization: {
                        try await viewModel.requestScreenTimeAuthorization()
                    },
                    onSave: { draft in
                        viewModel.addBlockedBehavior(draft)
                    }
                )
            }
        }
        .sheet(
            item: $presentedTimer,
            onDismiss: recordPendingTimerCompletion
        ) { timer in
            RoutineTimerView(
                routineTitle: timer.routineTitle,
                routineIconName: timer.routineIconName,
                targetMinutes: timer.targetMinutes,
                session: timer.session,
                onClose: { presentedTimer = nil },
                onStop: { stopTimer(timer) },
                onComplete: { completedAt in
                    completeTimer(timer, at: completedAt)
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
            .presentationBackground(AppColor.background)
        }
        .alert("削除できませんでした", isPresented: $isShowingBlockedBehaviorDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("時間をおいて、もう一度お試しください。")
        }
        .alert(
            "記録できませんでした",
            isPresented: Binding(
                get: { viewModel.routineOperationErrorMessage != nil },
                set: { if !$0 { viewModel.clearRoutineOperationError() } }
            )
        ) {
            if pendingTimerCompletion != nil {
                Button("再試行") {
                    viewModel.clearRoutineOperationError()
                    Task { @MainActor in
                        await Task.yield()
                        recordPendingTimerCompletion()
                    }
                }
                Button("閉じる", role: .cancel) {
                    pendingTimerCompletion = nil
                    viewModel.clearRoutineOperationError()
                }
            } else {
                Button("OK") {
                    viewModel.clearRoutineOperationError()
                }
            }
        } message: {
            Text(viewModel.routineOperationErrorMessage ?? "不明なエラーです")
        }
        .alert(
            "操作を完了できませんでした",
            isPresented: Binding(
                get: { viewModel.blockedBehaviorOperationErrorMessage != nil },
                set: { if !$0 { viewModel.clearBlockedBehaviorOperationError() } }
            )
        ) {
            Button("OK") {
                viewModel.clearBlockedBehaviorOperationError()
            }
        } message: {
            Text(viewModel.blockedBehaviorOperationErrorMessage ?? "不明なエラーです")
        }
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
            siriLaunchCoordinator.pendingOpenTodayRoutines = false
            refreshActiveTimer(at: .now)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, presentedTimer == nil {
                viewModel.reload()
                refreshActiveTimer(at: .now)
            }
        }
        .task(id: hiddenTimerWatcherID) {
            await watchHiddenTimer()
        }
        .sensoryFeedback(.success, trigger: backgroundTimerCompletionFeedbackTrigger)
    }

    private func blockedBehaviorEditor(for behavior: BlockedBehavior) -> some View {
        BlockedBehaviorCreateView(
            behavior: behavior,
            onRequestScreenTimeAuthorization: {
                try await viewModel.requestScreenTimeAuthorization()
            },
            onSave: { draft in
                viewModel.updateBlockedBehavior(behavior, with: draft)
            },
            onRequestDelete: {
                presentBlockedBehaviorDeleteConfirmation(for: behavior)
            }
        )
    }

    private func watchHiddenTimer() async {
        guard let timer = activeTimer,
              presentedTimer == nil,
              timer.session.phase == .running else { return }

        while !Task.isCancelled,
              activeTimer?.id == timer.id,
              presentedTimer == nil,
              timer.session.phase == .running {
            if let completedAt = timer.session.refresh(now: .now)
                ?? timer.session.completedAt {
                completeTimer(timer, at: completedAt)
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    // MARK: - 0. 今日の莉央

    @ViewBuilder
    private var rioHeaderSection: some View {
        if let comment = viewModel.rioComment {
            Section {
                RioHomeHeader(mood: viewModel.rioMood, text: comment.text) {
                    viewModel.selectNextRioComment()
                }
                .routineListRowStyle()
            }
        }
    }

    /// 約束が今回のタップ(またはタイマー)で目標に届いたときだけ、莉央が反応する。
    private func presentRioReactionIfNeeded(for routine: Routine, wasCompleted: Bool) {
        guard !wasCompleted,
              routine.id != onboardingRoutineID,
              viewModel.todayProgress(for: routine).isCompletedToday else { return }
        let allDone = viewModel.todayTotalCount > 0
            && viewModel.todayCompletedCount == viewModel.todayTotalCount
        let reaction = viewModel.makeRioReaction(allDone ? .allRoutinesCompleted : .routineCompleted)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            rioReaction = reaction
        }
        AccessibilityNotification.Announcement("莉央、\(reaction.text)").post()
    }

    private func dismissRioReaction() {
        withAnimation(.easeOut(duration: 0.2)) {
            rioReaction = nil
        }
    }

    // MARK: - 1. 今日の約束

    private var todayRoutinesSection: some View {
        Section {
            // 空の日は追加の入口をそのまま置く。編集はカード本体のタップで行う。
            if viewModel.todayRoutines.isEmpty {
                AddRoutineTaskRow {
                    isPresentingNewRoutine = true
                }
                .routineListRowStyle()
            }

            ForEach(viewModel.todayRoutines) { routine in
                routineListRow(routine)
                    .routineListRowStyle()
            }
        } header: {
            HStack(spacing: 8) {
                homeSectionTitle("今日の約束", systemImage: "checkmark.circle")
                Spacer()
                Text("\(viewModel.todayCompletedCount) / \(viewModel.todayTotalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColor.muted)
                Button {
                    isPresentingNewRoutine = true
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColor.primary)
                // 44pt のタップ領域を確保しつつ、見た目の位置は右端に揃える。
                .padding(.vertical, -8)
                .padding(.trailing, -8)
                .accessibilityLabel("約束を追加")
            }
            .textCase(nil)
        }
    }

    /// セクション見出し。アイコン幅を固定して、見出しの文字の開始位置を3セクションで揃える。
    private func homeSectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(title)
        }
        .font(.headline)
        .foregroundStyle(AppColor.text)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// 約束1件。カード本体は編集、時計はタイマー、右端の丸は達成状態の変更に分離する。
    @ViewBuilder
    private func routineListRow(_ routine: Routine) -> some View {
        let progress = viewModel.todayProgress(for: routine)
        let streak = viewModel.currentRoutineStreak(for: routine)
        let activeTimerForRoutine = activeTimer.flatMap {
            $0.routine.id == routine.id ? $0 : nil
        }

        RoutineTaskRow(
            title: routine.title,
            iconName: routine.iconName,
            cueText: routine.cueText,
            streakText: streak >= 1
                ? "\(streak)\(routine.period.streakUnitLabel)連続！"
                : "今日から",
            hasStreak: streak >= 1,
            progressText: progress.showsCountBreakdown
                ? "\(progress.done) / \(progress.target)回"
                : nil,
            progressFraction: progress.fraction,
            progressCount: progress.done,
            progressTarget: progress.target,
            timerStatusText: activeTimerForRoutine.map { timerStatusText(for: $0.session) },
            timerTargetDurationMinutes: routine.targetDurationMinutes,
            isTimerActive: activeTimerForRoutine != nil,
            isCompleted: progress.isCompletedToday,
            isHighlighted: false,
            allowsEditing: routine.id != onboardingRoutineID || highlightsDeferredReport,
            highlightsDeferredReport: highlightsDeferredReport && routine.id == onboardingRoutineID,
            completionActionTrigger: routine.id == onboardingRoutineID
                ? onboardingReportActionTrigger
                : 0,
            reportsCompletionButtonFrame: routine.id == onboardingRoutineID
                && !highlightsDeferredReport,
            onEdit: { requestRoutineEdit(routine) },
            onStartTimer: { openTimer(for: routine) },
            onAdvance: {
                let completesTarget = progress.done + 1 >= progress.target
                let didUpdate = updateRoutineCompletion(routine, completed: true)
                if didUpdate, completesTarget, routine.id == onboardingRoutineID {
                    onOnboardingRoutineCompleted()
                }
                if didUpdate {
                    presentRioReactionIfNeeded(for: routine, wasCompleted: progress.isCompletedToday)
                }
                return didUpdate
            },
            onUndoCompletion: {
                if rioReaction != nil {
                    dismissRioReaction()
                }
                return updateRoutineCompletion(routine, completed: false)
            },
            onCompletionButtonFrameChange: { frame in
                guard routine.id == onboardingRoutineID else { return }
                onOnboardingReportTargetFrameChange(frame)
            }
        )
    }

    // MARK: - 2. やらないこと

    @ViewBuilder
    private var todayPromiseSection: some View {
        Section {
            if let behavior = viewModel.currentBehavior {
                promiseCard(behavior)
                    .routineListRowStyle()
            } else {
                AddBlockedBehaviorTaskRow {
                    isPresentingNewBlockedBehavior = true
                }
                .routineListRowStyle()
            }

            if !viewModel.masteredBehaviors.isEmpty {
                DisclosureGroup("卒業したこと(\(viewModel.masteredBehaviors.count))") {
                    ForEach(viewModel.masteredBehaviors, id: \.id) { behavior in
                        Text(behavior.title)
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            viewModel.deleteMasteredBehavior(viewModel.masteredBehaviors[index])
                        }
                    }
                }
                .appCardRow()
            }
        } header: {
            homeSectionTitle("やらないこと", systemImage: "nosign")
                .textCase(nil)
        }
    }

    /// 「やらないこと」カード。カード本体は編集、右端の丸は危機／失敗の選択肢を表示する。
    @ViewBuilder
    private func promiseCard(_ behavior: BlockedBehavior) -> some View {
        let usage = viewModel.promiseUsage(for: behavior)
        let hasScreenTimeIssue = behavior.trackingKind == .screenTime
            && viewModel.screenTimeMonitoringIssueMessage != nil

        BlockedBehaviorTaskRow(
            title: behavior.title,
            iconName: behavior.iconName,
            statusText: promiseStatusText(
                behavior: behavior,
                usage: usage,
                hasScreenTimeIssue: hasScreenTimeIssue
            ),
            statusColor: promiseStatusColor(
                behavior: behavior,
                usage: usage,
                hasScreenTimeIssue: hasScreenTimeIssue
            ),
            detailText: promiseDetailText(
                behavior: behavior,
                usage: usage,
                hasScreenTimeIssue: hasScreenTimeIssue
            ),
            progressFraction: usage.fraction,
            isFailed: usage.failed,
            needsRepair: hasScreenTimeIssue,
            onEdit: {
                editingBlockedBehavior = behavior
            },
            onAction: {
                if hasScreenTimeIssue {
                    Task {
                        await viewModel.repairScreenTimeMonitoring(behavior)
                    }
                } else {
                    presentBlockedBehaviorActions(for: behavior)
                }
            }
        )
    }

    private func promiseStatusText(
        behavior: BlockedBehavior,
        usage: PromiseUsage,
        hasScreenTimeIssue: Bool
    ) -> String {
        if hasScreenTimeIssue { return "スクリーンタイムを再設定してください" }
        if usage.failed { return "失敗" }
        if behavior.currentStreakDays >= 1 { return "\(behavior.currentStreakDays)日達成！" }
        return "今日から"
    }

    private func promiseStatusColor(
        behavior: BlockedBehavior,
        usage: PromiseUsage,
        hasScreenTimeIssue: Bool
    ) -> Color {
        if hasScreenTimeIssue || usage.failed { return AppColor.error }
        return behavior.currentStreakDays >= 1 ? AppColor.success : AppColor.muted
    }

    private func promiseDetailText(
        behavior: BlockedBehavior,
        usage: PromiseUsage,
        hasScreenTimeIssue: Bool
    ) -> String? {
        if hasScreenTimeIssue { return "タップして許可を確認" }
        if usage.failed {
            return behavior.trackingKind == .screenTime
                ? "今日は時間上限を超えました"
                : "\(usage.periodLabel)は上限に達しました"
        }
        return behavior.trackingKind == .screenTime
            ? "今日は \(formattedScreenTimeLimit(behavior.screenTimeLimitMinutes)) まで"
            : "\(usage.periodLabel) あと \(usage.remaining) 回"
    }

    private func formattedScreenTimeLimit(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours == 0 { return "\(remainingMinutes)分" }
        if remainingMinutes == 0 { return "\(hours)時間" }
        return "\(hours)時間\(remainingMinutes)分"
    }

    private func presentBlockedBehaviorActions(for behavior: BlockedBehavior) {
        appDialog = AppDialogRequest(
            title: "「\(behavior.title)」",
            message: nil,
            actions: [
                AppDialogAction("負けそう…") {
                    .showTaunt(nextTaunt(for: .struggling))
                },
                AppDialogAction("負けました", style: .destructive) {
                    .replace(failureConfirmation(for: behavior))
                },
                AppDialogAction("閉じる", style: .cancel) {
                    .dismiss
                },
            ]
        )
    }

    private func presentBlockedBehaviorDeleteConfirmation(for behavior: BlockedBehavior) {
        appDialog = AppDialogRequest(
            title: "本当に削除しますか？",
            message: "「\(behavior.title)」を削除します。",
            actions: [
                AppDialogAction("いいえ") {
                    .dismiss
                },
                AppDialogAction("はい", style: .destructive) {
                    if viewModel.deleteBlockedBehavior(behavior) {
                        editingBlockedBehavior = nil
                    } else {
                        isShowingBlockedBehaviorDeleteError = true
                    }
                    return .dismiss
                },
            ]
        )
    }

    private func failureConfirmation(for behavior: BlockedBehavior) -> AppDialogRequest {
        AppDialogRequest(
            title: "本当に負けましたか？",
            message: "「\(behavior.title)」の失敗を記録します。",
            actions: [
                AppDialogAction("まだ耐える") {
                    .dismiss
                },
                AppDialogAction("負けました…", style: .destructive) {
                    guard viewModel.recordPromiseFailure(behavior) else {
                        return .dismiss
                    }
                    return .showTaunt(nextTaunt(for: .defeated))
                },
            ]
        )
    }

    private func nextTaunt(for kind: BlockedBehaviorTauntKind) -> BlockedBehaviorTauntRequest {
        let index: Int
        switch kind {
        case .struggling:
            index = nextStrugglingTauntIndex % kind.messages.count
            nextStrugglingTauntIndex = (nextStrugglingTauntIndex + 1) % kind.messages.count
        case .defeated:
            index = nextDefeatedTauntIndex % kind.messages.count
            nextDefeatedTauntIndex = (nextDefeatedTauntIndex + 1) % kind.messages.count
        }
        return BlockedBehaviorTauntRequest(text: kind.messages[index])
    }

    // MARK: - 3. みんなのざこ速報

    private var zakoBulletinSection: some View {
        Section {
            // 約束・やらないことのカードと同じ幅・角丸に揃える。
            ZakoBulletinFeedView(items: viewModel.zakoBulletinItems)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColor.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(AppColor.border.opacity(0.72), lineWidth: 1)
                }
                .shadow(color: AppColor.text.opacity(0.035), radius: 7, y: 3)
                .routineListRowStyle()
        } header: {
            homeSectionTitle("みんなのざこ速報", systemImage: "ellipsis.bubble")
                .textCase(nil)
        }
    }

    private func updateRoutineCompletion(_ routine: Routine, completed: Bool) -> Bool {
        let didUpdate = completed
            ? viewModel.advanceRoutine(routine)
            : viewModel.setRoutineCompletion(routine, completed: false)
        if didUpdate,
           completed,
           let timer = activeTimer,
           timer.routine.id == routine.id {
            stopTimer(timer)
        }
        return didUpdate
    }

    private func recordPendingTimerCompletion() {
        guard let pendingTimerCompletion else { return }
        let routine = pendingTimerCompletion.routine
        let progress = viewModel.todayProgress(for: routine)
        let completesTarget = progress.done + 1 >= progress.target
        if viewModel.advanceRoutine(
            routine,
            now: pendingTimerCompletion.completedAt
        ) {
            self.pendingTimerCompletion = nil
            if completesTarget, routine.id == onboardingRoutineID {
                onOnboardingRoutineCompleted()
            }
            presentRioReactionIfNeeded(for: routine, wasCompleted: progress.isCompletedToday)
        }
    }

    private func openTimer(for routine: Routine) {
        if let activeTimer {
            if let completedAt = activeTimer.session.refresh(now: .now)
                ?? activeTimer.session.completedAt {
                completeTimer(activeTimer, at: completedAt)
                return
            }

            if activeTimer.routine.id == routine.id {
                presentedTimer = activeTimer
            } else {
                presentTimerReplacementConfirmation(
                    runningTimer: activeTimer,
                    newRoutine: routine
                )
            }
            return
        }

        startTimer(for: routine)
    }

    private func startTimer(for routine: Routine) {
        let timer = ActiveRoutineTimer(routine: routine)
        activeTimer = timer
        presentedTimer = timer
    }

    private func requestRoutineEdit(_ routine: Routine) {
        guard let runningTimer = activeTimer,
              runningTimer.routine.id == routine.id else {
            editingRoutine = routine
            return
        }

        if let completedAt = runningTimer.session.refresh(now: .now)
            ?? runningTimer.session.completedAt {
            completeTimer(runningTimer, at: completedAt)
            return
        }

        let request = AppDialogRequest(
            title: "タイマーを停止しますか？",
            message: "「\(runningTimer.routineTitle)」を編集するには、動作中のタイマーを停止してください。",
            actions: [
                AppDialogAction("戻る") {
                    timerDialogID = nil
                    return .dismiss
                },
                AppDialogAction("停止して編集", style: .destructive) {
                    timerDialogID = nil
                    guard activeTimer?.id == runningTimer.id else { return .dismiss }
                    if let completedAt = runningTimer.session.refresh(now: .now)
                        ?? runningTimer.session.completedAt {
                        completeTimer(runningTimer, at: completedAt)
                        return .dismiss
                    }
                    stopTimer(runningTimer)
                    editingRoutine = routine
                    return .dismiss
                },
            ]
        )
        timerDialogID = request.id
        appDialog = request
    }

    private func presentTimerReplacementConfirmation(
        runningTimer: ActiveRoutineTimer,
        newRoutine: Routine
    ) {
        let request = AppDialogRequest(
            title: "別のタイマーが動作中です",
            message: "「\(runningTimer.routineTitle)」を停止して「\(newRoutine.title)」を開始しますか？",
            actions: [
                AppDialogAction("今のタイマーを見る") {
                    timerDialogID = nil
                    guard activeTimer?.id == runningTimer.id else { return .dismiss }
                    if let completedAt = runningTimer.session.refresh(now: .now)
                        ?? runningTimer.session.completedAt {
                        completeTimer(runningTimer, at: completedAt)
                        return .dismiss
                    }
                    presentedTimer = runningTimer
                    return .dismiss
                },
                AppDialogAction("切り替える", style: .destructive) {
                    timerDialogID = nil
                    guard activeTimer?.id == runningTimer.id else { return .dismiss }
                    if let completedAt = runningTimer.session.refresh(now: .now)
                        ?? runningTimer.session.completedAt {
                        completeTimer(runningTimer, at: completedAt)
                        return .dismiss
                    }
                    stopTimer(runningTimer)
                    startTimer(for: newRoutine)
                    return .dismiss
                },
            ]
        )
        timerDialogID = request.id
        appDialog = request
    }

    private func refreshActiveTimer(at date: Date) {
        guard let activeTimer else { return }
        if let completedAt = activeTimer.session.refresh(now: date)
            ?? activeTimer.session.completedAt {
            completeTimer(activeTimer, at: completedAt)
        }
    }

    private func completeTimer(_ timer: ActiveRoutineTimer, at completedAt: Date) {
        guard activeTimer?.id == timer.id else { return }
        activeTimer = nil
        if let timerDialogID, appDialog?.id == timerDialogID {
            appDialog = nil
        }
        timerDialogID = nil

        if presentedTimer?.id == timer.id {
            pendingTimerCompletion = PendingTimerCompletion(
                routine: timer.routine,
                completedAt: completedAt
            )
            presentedTimer = nil
        } else {
            backgroundTimerCompletionFeedbackTrigger += 1
            pendingTimerCompletion = PendingTimerCompletion(
                routine: timer.routine,
                completedAt: completedAt
            )
            recordPendingTimerCompletion()
        }
    }

    private func stopTimer(_ timer: ActiveRoutineTimer) {
        guard activeTimer?.id == timer.id else { return }
        timer.session.stop()
        activeTimer = nil
        if presentedTimer?.id == timer.id {
            presentedTimer = nil
        }
    }

    private func timerStatusText(for session: RoutineTimerSession) -> String {
        switch session.phase {
        case .running:
            "残り \(session.formattedRemainingDuration)"
        case .paused:
            "一時停止 \(session.formattedRemainingDuration)"
        case .completed:
            "目標達成"
        case .stopped:
            "停止中"
        }
    }
}

private final class ActiveRoutineTimer: Identifiable {
    let id = UUID()
    let routine: Routine
    let routineTitle: String
    let routineIconName: String?
    let targetMinutes: Int
    let session: RoutineTimerSession

    @MainActor
    init(routine: Routine, now: Date = .now) {
        self.routine = routine
        routineTitle = routine.title
        routineIconName = routine.iconName
        targetMinutes = max(routine.targetDurationMinutes ?? 1, 1)
        session = RoutineTimerSession(
            targetMinutes: targetMinutes,
            now: now
        )
    }
}

private struct PendingTimerCompletion {
    let routine: Routine
    let completedAt: Date
}

enum BlockedBehaviorTauntKind {
    case struggling
    case defeated

    var messages: [String] {
        switch self {
        case .struggling:
            return [
                "よわよわメンタル出てきたね♡",
                "負けそうだから莉央ちゃんに助け求めにきたんだw",
                "はいはい、見ててあげるから我慢して〜",
            ]
        case .defeated:
            return [
                "ほんとに負けてきたの？w",
                "わざわざ敗北報告しに来たんだ♡",
                "うわ、大人なのに我慢できなかったんだ〜",
            ]
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
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
