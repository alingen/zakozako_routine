import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = HomeViewModel()
    @State private var editingRoutine: Routine?
    @State private var activeTimer: ActiveRoutineTimer?
    @State private var presentedTimer: ActiveRoutineTimer?
    @State private var pendingTimerCompletion: PendingTimerCompletion?
    @State private var timerDialogID: UUID?
    @State private var backgroundTimerCompletionFeedbackTrigger = 0
    @State private var isPresentingNewRoutine = false
    @State private var isEditingRoutines = false
    @State private var isPresentingNewBlockedBehavior = false
    @State private var isShowingBlockedBehaviorDeleteError = false
    @State private var nextStrugglingTauntIndex = 0
    @State private var nextDefeatedTauntIndex = 0

    @Binding private var appDialog: AppDialogRequest?

    private let routineGridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    init(appDialog: Binding<AppDialogRequest?> = .constant(nil)) {
        _appDialog = appDialog
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
            todayRoutinesSection
            todayPromiseSection
            zakoBulletinSection
        }
        .appScreenBackground()
        .navigationDestination(item: $editingRoutine) { routine in
            RoutineEditView(routine: routine)
        }
        .onChange(of: editingRoutine) { _, new in
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
        .fullScreenCover(
            item: Binding(
                get: { viewModel.completionContext },
                set: { if $0 == nil { viewModel.clearCompletion() } }
            )
        ) { context in
            RoutineCompletionPresentation(context: context, onFinish: { viewModel.clearCompletion() })
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
        .sensoryFeedback(.success, trigger: backgroundTimerCompletionFeedbackTrigger)
    }

    // MARK: - 1. 今日の約束(2列グリッド)

    private var todayRoutinesSection: some View {
        Section {
            if viewModel.todayRoutines.isEmpty && !isEditingRoutines {
                Text("今日の約束はありません")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
            } else {
                LazyVGrid(columns: routineGridColumns, spacing: 14) {
                    ForEach(viewModel.todayRoutines) { routine in
                        routineGridCell(routine)
                    }
                    if isEditingRoutines {
                        addRoutineCell
                    }
                }
                .padding(.vertical, 6)
                .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                // 編集モード中、円以外(余白・タイトル)をタップしたら編集を終える。
                .contentShape(Rectangle())
                .onTapGesture {
                    if isEditingRoutines { isEditingRoutines = false }
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text("今日の約束")
                Spacer()
                Text("\(viewModel.todayCompletedCount) / \(viewModel.todayTotalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColor.muted)
                Button {
                    isEditingRoutines.toggle()
                } label: {
                    Image(systemName: isEditingRoutines ? "checkmark" : "square.and.pencil")
                        .font(.title3.weight(.semibold))
                        // グリフごとの高さ差でヘッダーがガタつかないよう、表示枠を固定する。
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(AppColor.primary)
                .accessibilityLabel(isEditingRoutines ? "編集を終える" : "約束を編集")
            }
        }
        .appCardRow()
    }

    /// 約束1件の大きな円セル。通常はホールド、タイマー対象はタップで開始、編集中はタップで編集する。
    @ViewBuilder
    private func routineGridCell(_ routine: Routine) -> some View {
        let progress = viewModel.todayProgress(for: routine)
        let streak = viewModel.currentRoutineStreak(for: routine)
        let activeTimerForRoutine = activeTimer.flatMap {
            $0.routine.id == routine.id ? $0 : nil
        }

        VStack(spacing: 8) {
            RoutineProgressButton(
                progress: progress.fraction,
                iconName: routine.iconName,
                isEditing: isEditingRoutines,
                isCompleted: progress.isCompletedToday,
                timerTargetDurationMinutes: routine.targetDurationMinutes,
                isTimerActive: activeTimerForRoutine != nil,
                accessibilityLabel: routine.title,
                onAdvance: { viewModel.advanceRoutine(routine) },
                onStartTimer: { openTimer(for: routine) },
                onEdit: { requestRoutineEdit(routine) }
            )

            VStack(spacing: 2) {
                Text(routine.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if let activeTimerForRoutine {
                    Text(timerStatusText(for: activeTimerForRoutine.session))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(AppColor.primary)
                } else if progress.showsCountBreakdown {
                    Text("\(progress.done) / \(progress.target)回")
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                } else if streak >= 1 {
                    Text("\(streak)\(routine.period.streakUnitLabel)達成！")
                        .font(.caption2)
                        .foregroundStyle(AppColor.success)
                } else {
                    Text("今日から")
                        .font(.caption2)
                        .foregroundStyle(AppColor.muted)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 編集モードのときだけ出る「約束を追加」セル。
    private var addRoutineCell: some View {
        Button {
            isPresentingNewRoutine = true
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 116, height: 116)
                    .overlay(Circle().stroke(AppColor.border, lineWidth: 7))
                Text("約束を追加")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(" ")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. やらないこと

    @ViewBuilder
    private var todayPromiseSection: some View {
        Section("やらないこと") {
            if let behavior = viewModel.currentBehavior {
                promiseCard(behavior)
                    .padding(.vertical, 4)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            appDialog = AppDialogRequest(
                                title: "本当に削除しますか？",
                                message: "「\(behavior.title)」を削除します。",
                                actions: [
                                    AppDialogAction("いいえ") {
                                        .dismiss
                                    },
                                    AppDialogAction("はい", style: .destructive) {
                                        if !viewModel.deleteBlockedBehavior(behavior) {
                                            isShowingBlockedBehaviorDeleteError = true
                                        }
                                        return .dismiss
                                    },
                                ]
                            )
                        } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
            } else {
                Button {
                    isPresentingNewBlockedBehavior = true
                } label: {
                    Label("やらないことを決める", systemImage: "hand.raised")
                }
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
            }
        }
        .appCardRow()
    }

    /// 「やらないこと」カード。タップすると危機／失敗の選択肢を表示する。
    @ViewBuilder
    private func promiseCard(_ behavior: BlockedBehavior) -> some View {
        let usage = viewModel.promiseUsage(for: behavior)
        let hasScreenTimeIssue = behavior.trackingKind == .screenTime
            && viewModel.screenTimeMonitoringIssueMessage != nil

        Button {
            if hasScreenTimeIssue {
                Task {
                    await viewModel.repairScreenTimeMonitoring(behavior)
                }
            } else {
                presentBlockedBehaviorActions(for: behavior)
            }
        } label: {
            HStack(spacing: 12) {
                ProgressCircle(
                    progress: usage.fraction,
                    size: 34,
                    tint: AppColor.primary,
                    showsCheckmarkWhenComplete: false,
                    failed: usage.failed,
                    centerSystemImage: behavior.iconName
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(behavior.title)
                        .font(.headline)
                        .foregroundStyle(AppColor.text)

                    if hasScreenTimeIssue {
                        Text("スクリーンタイムを再設定してください")
                            .font(.caption)
                            .foregroundStyle(AppColor.error)
                        Text("タップして許可を確認")
                            .font(.caption2)
                            .foregroundStyle(AppColor.muted)
                    } else if usage.failed {
                        Text(
                            behavior.trackingKind == .screenTime
                                ? "今日は時間上限を超えました"
                                : "\(usage.periodLabel)は上限に達しました"
                        )
                            .font(.caption)
                            .foregroundStyle(AppColor.error)
                    } else {
                        if behavior.currentStreakDays >= 1 {
                            Text("\(behavior.currentStreakDays)日達成！")
                                .font(.caption)
                                .foregroundStyle(AppColor.success)
                        } else {
                            Text("今日から")
                                .font(.caption)
                                .foregroundStyle(AppColor.muted)
                        }

                        Text(
                            behavior.trackingKind == .screenTime
                                ? "今日は \(formattedScreenTimeLimit(behavior.screenTimeLimitMinutes)) まで"
                                : "\(usage.periodLabel) あと \(usage.remaining) 回"
                        )
                            .font(.caption2)
                            .foregroundStyle(AppColor.muted)
                    }
                }
                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            title: nil,
            message: "「\(behavior.title)」",
            actions: [
                AppDialogAction("負けそう…") {
                    .showTaunt(nextTaunt(for: .struggling))
                },
                AppDialogAction("負けました", style: .destructive) {
                    .replace(failureConfirmation(for: behavior))
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
        Section("みんなのざこ速報") {
            ZakoBulletinFeedView(items: viewModel.zakoBulletinItems)
        }
        .appCardRow()
    }

    private func recordPendingTimerCompletion() {
        guard let pendingTimerCompletion else { return }
        if viewModel.advanceRoutine(
            pendingTimerCompletion.routine,
            now: pendingTimerCompletion.completedAt
        ) {
            self.pendingTimerCompletion = nil
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

/// 短いタップでは反応せず、円が中央から外周まで広がる長押しで進捗を記録する。
private struct RoutineProgressButton: View {
    private static let holdDuration: TimeInterval = 0.8

    let progress: Double
    let iconName: String?
    let isEditing: Bool
    let isCompleted: Bool
    let timerTargetDurationMinutes: Int?
    let isTimerActive: Bool
    let accessibilityLabel: String
    let onAdvance: () -> Void
    let onStartTimer: () -> Void
    let onEdit: () -> Void

    @State private var confirmationProgress = 0.0
    @State private var isHoldConfirmed = false
    @State private var confirmationFeedbackTrigger = 0

    var body: some View {
        Group {
            if isEditing {
                Button(action: onEdit) {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityHint("タップして編集")
            } else if isCompleted {
                content
                    .accessibilityValue("達成済み")
                    .accessibilityHint("次の集計期間まで記録できません")
            } else if let timerTargetDurationMinutes {
                Button(action: onStartTimer) {
                    content
                }
                .buttonStyle(.plain)
                .accessibilityHint(
                    isTimerActive
                        ? "タップして動作中のタイマーを表示"
                        : "タップして\(timerTargetDurationMinutes)分のタイマーを開始"
                )
            } else {
                content
                    .onLongPressGesture(
                        minimumDuration: Self.holdDuration,
                        maximumDistance: 24,
                        perform: confirmHold,
                        onPressingChanged: updateHoldingState
                    )
                    // LongPressGestureは成立時に終了するため、指を離した瞬間は並行するDragGestureで拾う。
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { _ in finishHold() }
                    )
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("長押しして1回分を記録")
                    .accessibilityAction(named: "1回分を記録", onAdvance)
            }
        }
        .accessibilityLabel(
            timerTargetDurationMinutes == nil || isEditing
                ? accessibilityLabel
                : "\(accessibilityLabel)のタイマー"
        )
        .accessibilityValue(progressAccessibilityValue)
        .sensoryFeedback(.success, trigger: confirmationFeedbackTrigger)
        .onChange(of: isEditing) {
            resetConfirmation()
        }
        .onChange(of: isCompleted) {
            if isCompleted { resetConfirmation() }
        }
    }

    private var content: some View {
        ZStack(alignment: .bottomTrailing) {
            RoutineProgressPie(
                progress: progress,
                size: 116,
                centerSystemImage: iconName,
                confirmationProgress: confirmationProgress,
                showsConfirmationCheckmark: isHoldConfirmed
            )
            if isEditing || (timerTargetDurationMinutes != nil && !isCompleted) {
                Image(systemName: isEditing ? "ellipsis" : "clock.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        isEditing
                            ? AppColor.text
                            : (isTimerActive ? Color.white : AppColor.primary)
                    )
                    .frame(width: 36, height: 36)
                    .background(
                        isTimerActive && !isEditing ? AppColor.primary : AppColor.surface,
                        in: Circle()
                    )
                    .overlay(Circle().stroke(AppColor.border, lineWidth: 1))
                    .offset(x: 4, y: 4)
            }
        }
        .contentShape(Circle())
    }

    private var progressAccessibilityValue: String {
        if isCompleted { return "達成済み" }
        if isTimerActive { return "動作中" }
        return ""
    }

    private func updateHoldingState(_ isHolding: Bool) {
        if isHolding {
            isHoldConfirmed = false
            confirmationProgress = 0
            withAnimation(.linear(duration: Self.holdDuration)) {
                confirmationProgress = 1
            }
        } else if !isHoldConfirmed {
            resetConfirmation()
        }
    }

    /// 円が満たされた時点で振動とチェック表示を確定し、記録自体は指を離すまで待つ。
    private func confirmHold() {
        guard !isCompleted, !isHoldConfirmed else { return }
        isHoldConfirmed = true
        confirmationProgress = 1
        confirmationFeedbackTrigger += 1
    }

    private func finishHold() {
        let shouldAdvance = isHoldConfirmed && !isCompleted
        resetConfirmation()
        if shouldAdvance {
            onAdvance()
        }
    }

    private func resetConfirmation() {
        isHoldConfirmed = false
        withAnimation(.easeOut(duration: 0.18)) {
            confirmationProgress = 0
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
