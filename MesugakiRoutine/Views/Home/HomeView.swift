import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @State private var viewModel = HomeViewModel()
    @State private var editingRoutine: Routine?
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
                BlockedBehaviorCreateView { draft in
                    viewModel.addBlockedBehavior(draft)
                }
            }
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
            Button("OK") {
                viewModel.clearRoutineOperationError()
            }
        } message: {
            Text(viewModel.routineOperationErrorMessage ?? "不明なエラーです")
        }
        .alert(
            "失敗を記録できませんでした",
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
        }
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

    /// 約束1件の大きな円セル。通常時は円のホールドで1回進む / 編集時はタップで編集画面へ。
    @ViewBuilder
    private func routineGridCell(_ routine: Routine) -> some View {
        let progress = viewModel.todayProgress(for: routine)
        let streak = viewModel.currentRoutineStreak(for: routine)

        VStack(spacing: 8) {
            RoutineProgressButton(
                progress: progress.fraction,
                iconName: routine.iconName,
                isEditing: isEditingRoutines,
                isCompleted: progress.isCompletedToday,
                accessibilityLabel: routine.title,
                onAdvance: { viewModel.advanceRoutine(routine) },
                onEdit: { editingRoutine = routine }
            )

            VStack(spacing: 2) {
                Text(routine.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                if progress.showsCountBreakdown {
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

        Button {
            presentBlockedBehaviorActions(for: behavior)
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

                    if usage.failed {
                        Text("\(usage.periodLabel)は上限に達しました")
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

                        Text("\(usage.periodLabel) あと \(usage.remaining) 回")
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
    let accessibilityLabel: String
    let onAdvance: () -> Void
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
        .accessibilityLabel(accessibilityLabel)
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
            if isEditing {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.text)
                    .frame(width: 30, height: 30)
                    .background(AppColor.surface, in: Circle())
                    .overlay(Circle().stroke(AppColor.border, lineWidth: 1))
                    .offset(x: 4, y: 4)
            }
        }
        .contentShape(Circle())
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
