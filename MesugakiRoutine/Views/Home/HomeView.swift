import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @State private var viewModel = HomeViewModel()
    @State private var editingRoutine: Routine?
    @State private var isPresentingNewRoutine = false
    @State private var editingBehavior: BlockedBehavior?
    @State private var showAddPromiseForm = false

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

    // MARK: - 1. 今日のルーティン

    private var todayRoutinesSection: some View {
        Section {
            if viewModel.todayRoutines.isEmpty {
                Text("今日のルーティンはありません")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
            } else {
                ForEach(viewModel.todayRoutines) { routine in
                    routineRow(routine)
                        .swipeActions(edge: .trailing) {
                            Button("削除", role: .destructive) { viewModel.deleteRoutine(routine) }
                            Button("編集") { editingRoutine = routine }
                                .tint(AppColor.secondary)
                        }
                }
            }
        } header: {
            HStack(spacing: 8) {
                Text("今日のルーティン")
                Spacer()
                Text("\(viewModel.todayCompletedCount) / \(viewModel.todayTotalCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(AppColor.muted)
                Button {
                    isPresentingNewRoutine = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(AppColor.primary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("ルーティンを追加")
            }
        }
        .appCardRow()
    }

    /// タップで1ステップ進む。最後のステップ(または0ステップ)で完了。
    @ViewBuilder
    private func routineRow(_ routine: Routine) -> some View {
        let progress = viewModel.todayProgress(for: routine)
        let streak = viewModel.currentRoutineStreak(for: routine)
        let inProgressStep = viewModel.inProgressStepTitle(for: routine)

        Button {
            withAnimation { viewModel.advanceRoutine(routine) }
        } label: {
            HStack(spacing: 12) {
                ProgressCircle(progress: progress.fraction, size: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.title)
                        .font(.headline)
                        .foregroundStyle(AppColor.text)

                    if progress.showsStepBreakdown, !progress.isCompletedToday {
                        Text("\(progress.completedSteps) / \(progress.totalSteps)ステップ")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }

                    if streak >= 1 {
                        Text("\(streak)日達成！")
                            .font(.caption)
                            .foregroundStyle(AppColor.success)
                    } else {
                        Text("今日から始めよう")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }
                }

                Spacer(minLength: 8)

                if let inProgressStep {
                    Text(inProgressStep)
                        .font(.caption)
                        .foregroundStyle(AppColor.primary)
                        .lineLimit(1)
                } else if !progress.isCompletedToday {
                    Text("タップで進める")
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                } else if let minute = routine.scheduledStartMinute {
                    Text(Self.timeText(minute))
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - 2. 今日の約束

    @ViewBuilder
    private var todayPromiseSection: some View {
        Section("今日の約束") {
            if let behavior = viewModel.currentBehavior {
                promiseCard(behavior)
                    .padding(.vertical, 4)
            } else if showAddPromiseForm {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("約束(例: YouTubeを見ない)", text: $viewModel.newBlockedBehaviorTitle)
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
                    Label("今日の約束を決める", systemImage: "hand.raised")
                }
            }

            if !viewModel.masteredBehaviors.isEmpty {
                DisclosureGroup("卒業した約束(\(viewModel.masteredBehaviors.count))") {
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
                withAnimation { viewModel.consumePromise(behavior) }
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
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(AppColor.muted)
        }
    }

    // MARK: - 3. みんなのざこ速報

    private var zakoBulletinSection: some View {
        Section("みんなのざこ速報") {
            ZakoBulletinFeedView(items: viewModel.zakoBulletinItems)
        }
        .appCardRow()
    }

    // MARK: - helpers

    private static func timeText(_ minute: Int) -> String {
        String(format: "%d:%02d", minute / 60, minute % 60)
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
