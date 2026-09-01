import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @State private var viewModel = HomeViewModel()
    @State private var editingRoutine: Routine?
    @State private var isPresentingNewRoutine = false
    @State private var isEditingRoutines = false
    @State private var editingBehavior: BlockedBehavior?
    @State private var showAddPromiseForm = false

    private let routineGridColumns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

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
        .fullScreenCover(
            item: Binding(
                get: { viewModel.completionContext },
                set: { if $0 == nil { viewModel.clearCompletion() } }
            )
        ) { context in
            RoutineCompletionPresentation(context: context, onFinish: { viewModel.clearCompletion() })
        }
        .sheet(item: $editingBehavior) { behavior in
            BlockedBehaviorDetailView(behavior: behavior) { title, limitPeriod, limitCount in
                viewModel.updateBlockedBehaviorDetails(
                    behavior,
                    title: title,
                    limitPeriod: limitPeriod,
                    limitCount: limitCount
                )
            }
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

    /// ルーティン1件の大きな円セル。通常時タップで1ステップ進む / 編集時タップで編集画面へ。
    @ViewBuilder
    private func routineGridCell(_ routine: Routine) -> some View {
        let progress = viewModel.todayProgress(for: routine)
        let streak = viewModel.currentRoutineStreak(for: routine)

        Button {
            if isEditingRoutines {
                editingRoutine = routine
            } else {
                viewModel.advanceRoutine(routine)
            }
        } label: {
            VStack(spacing: 8) {
                ZStack(alignment: .bottomTrailing) {
                    ProgressCircle(
                        progress: progress.fraction,
                        size: 116,
                        lineWidth: 7,
                        centerSystemImage: routine.iconName
                    )
                    if isEditingRoutines {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AppColor.text)
                            .frame(width: 30, height: 30)
                            .background(AppColor.surface, in: Circle())
                            .overlay(Circle().stroke(AppColor.border, lineWidth: 1))
                            .offset(x: 4, y: 4)
                    }
                }

                VStack(spacing: 2) {
                    Text(routine.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(AppColor.text)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)

                    if progress.showsStepBreakdown, !progress.isCompletedToday {
                        Text("\(progress.completedSteps) / \(progress.totalSteps)ステップ")
                            .font(.caption2)
                            .foregroundStyle(AppColor.muted)
                    } else if streak >= 1 {
                        Text("\(streak)日達成！")
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
            } else if showAddPromiseForm {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("やらないこと(例: YouTubeを見ない)", text: $viewModel.newBlockedBehaviorTitle)
                    Picker("ペース", selection: $viewModel.newBlockedBehaviorLimitPeriod) {
                        ForEach(BlockedBehaviorLimitPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    Stepper(
                        "\(viewModel.newBlockedBehaviorLimitPeriod.displayName) \(viewModel.newBlockedBehaviorLimitCount) 回で✕",
                        value: $viewModel.newBlockedBehaviorLimitCount,
                        in: 1...50
                    )
                    Button("決定") {
                        viewModel.addBlockedBehavior()
                        showAddPromiseForm = false
                    }
                    .disabled(viewModel.newBlockedBehaviorTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else {
                Button {
                    showAddPromiseForm = true
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

    /// 「今日の約束」カード。ルーティン行と同じ左丸マーク。丸マーク＋タイトルのタップで1回消費。
    @ViewBuilder
    private func promiseCard(_ behavior: BlockedBehavior) -> some View {
        let usage = viewModel.promiseUsage(for: behavior)

        HStack(spacing: 12) {
            Button {
                viewModel.consumePromise(behavior)
            } label: {
                HStack(spacing: 12) {
                    ProgressCircle(
                        progress: usage.fraction,
                        size: 34,
                        tint: AppColor.primary,
                        showsCheckmarkWhenComplete: false,
                        failed: usage.failed
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(behavior.title)
                            .font(.headline)
                            .foregroundStyle(AppColor.text)

                        if behavior.currentStreakDays >= 1 {
                            Text("\(behavior.currentStreakDays)日達成！")
                                .font(.caption)
                                .foregroundStyle(AppColor.success)
                        } else {
                            Text("今日から")
                                .font(.caption)
                                .foregroundStyle(AppColor.muted)
                        }

                        if usage.failed {
                            Text("\(usage.periodLabel)は上限に達しました")
                                .font(.caption2)
                                .foregroundStyle(AppColor.error)
                        } else {
                            Text("\(usage.periodLabel) あと \(usage.remaining) 回")
                                .font(.caption2)
                                .foregroundStyle(AppColor.muted)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Button {
                editingBehavior = behavior
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppColor.muted)
            .accessibilityLabel("やらないことを編集")
        }
    }

    // MARK: - 3. みんなのざこ速報

    private var zakoBulletinSection: some View {
        Section("みんなのざこ速報") {
            ZakoBulletinFeedView(items: viewModel.zakoBulletinItems)
        }
        .appCardRow()
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(SiriLaunchCoordinator())
    .modelContainer(
        for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self, BlockedBehavior.self],
        inMemory: true
    )
}
