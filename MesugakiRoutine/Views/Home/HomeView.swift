import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @State private var viewModel = HomeViewModel()
    @State private var selectedRoutine: Routine?
    @State private var editingRoutine: Routine?
    @State private var isPresentingNewRoutine = false
    @State private var isPresentingTemptationMessage = false
    @State private var temptationMessage = ""
    @State private var editingBehavior: BlockedBehavior?
    @State private var presentedEvent: EventDefinition?
    @State private var showAddPromiseForm = false

    var body: some View {
        List {
            eventTeaserSection
            todayRoutinesSection
            todayPromiseSection
            zakoBulletinSection
        }
        .appScreenBackground()
        .navigationDestination(item: $selectedRoutine) { routine in
            RoutineSessionView(routine: routine)
        }
        .navigationDestination(item: $editingRoutine) { routine in
            RoutineEditView(routine: routine)
        }
        .sheet(isPresented: $isPresentingNewRoutine, onDismiss: { viewModel.reload() }) {
            NavigationStack {
                RoutineEditView(routine: nil)
            }
        }
        .alert("小悪魔コーチより", isPresented: $isPresentingTemptationMessage) {
            Button("がんばる", role: .cancel) {}
        } message: {
            Text(temptationMessage)
        }
        .fullScreenCover(item: $presentedEvent, onDismiss: { viewModel.reload() }) { event in
            NavigationStack {
                EventPlayerView(event: event)
            }
        }
        .fullScreenCover(
            item: Binding(
                get: { viewModel.completionContext },
                set: { if $0 == nil { viewModel.clearCompletion() } }
            )
        ) { context in
            RoutineCompletionPresentation(
                context: context,
                // 現状クイック完了は offersTodayConversation == false なのでこの分岐は呼ばれない。
                // TODO(Step 6): 「今日のルーティン全完了」で今日の会話へ繋ぐ。
                onStartTodayConversation: { viewModel.clearCompletion() },
                onFinish: { viewModel.clearCompletion() }
            )
        }
        .sheet(item: $editingBehavior) { behavior in
            BlockedBehaviorDetailView(behavior: behavior) { reason, alternativeAction, triggerText, useTimeWindow, start, end, limitPeriod, limitCount in
                viewModel.updateBlockedBehaviorDetails(
                    behavior,
                    reason: reason,
                    alternativeAction: alternativeAction,
                    triggerText: triggerText,
                    useTimeWindow: useTimeWindow,
                    startTime: start,
                    endTime: end,
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
            startPendingRoutineIfNeeded()
        }
        .onChange(of: siriLaunchCoordinator.pendingOpenTodayRoutines) {
            startPendingRoutineIfNeeded()
        }
    }

    // MARK: - イベント予告(既存機能)

    @ViewBuilder
    private var eventTeaserSection: some View {
        if let event = viewModel.presentableEvent {
            Section {
                Button {
                    presentedEvent = event
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "envelope.badge.fill")
                            .foregroundStyle(AppColor.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.characterName)が話したいことがあるみたい")
                                .font(.subheadline.bold())
                                .foregroundStyle(AppColor.text)
                            Text("タップして話を聞く")
                                .font(.caption)
                                .foregroundStyle(AppColor.muted)
                        }
                    }
                }
            }
            .appCardRow()
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

    @ViewBuilder
    private func routineRow(_ routine: Routine) -> some View {
        let progress = viewModel.todayProgress(for: routine)
        let streak = viewModel.currentRoutineStreak(for: routine)
        let inProgressStep = viewModel.inProgressStepTitle(for: routine)
        let isQuick = viewModel.isQuickCompletable(routine)

        Button {
            if isQuick {
                withAnimation { viewModel.quickComplete(routine) }
            } else {
                selectedRoutine = routine
            }
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
                        Text("\(streak)日継続中！")
                            .font(.caption)
                            .foregroundStyle(AppColor.success)
                    } else {
                        Text("今日から始めよう")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }
                }

                Spacer(minLength: 8)

                if inProgressStep != nil {
                    Text("再開")
                        .font(.caption.bold())
                        .foregroundStyle(AppColor.primary)
                } else if isQuick, !progress.isCompletedToday {
                    Text("タップで完了")
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

    // MARK: - 2. 今日の約束(BlockedBehavior。ルーティン一覧には混ぜない)

    @ViewBuilder
    private var todayPromiseSection: some View {
        Section("今日の約束") {
            if let behavior = viewModel.currentBehavior {
                promiseCard(behavior)
                    .padding(.vertical, 4)
            } else if showAddPromiseForm {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("約束(例: YouTubeを見ない)", text: $viewModel.newBlockedBehaviorTitle)
                    TextField("理由(例: 仕事をさぼらないため)", text: $viewModel.newBlockedBehaviorReason)
                    TextField("代替行動(例: 音楽をかける)", text: $viewModel.newBlockedBehaviorAlternativeAction)
                    Picker("ペース", selection: $viewModel.newBlockedBehaviorLimitPeriod) {
                        ForEach(BlockedBehaviorLimitPeriod.allCases) { period in
                            Text(period.displayName).tag(period)
                        }
                    }
                    Stepper(
                        "\(viewModel.newBlockedBehaviorLimitPeriod.displayName) \(viewModel.newBlockedBehaviorLimitCount) 回まで",
                        value: $viewModel.newBlockedBehaviorLimitCount,
                        in: 0...50
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

    /// 「今日の約束」カード本体。ルーティン行と同じく左に丸マーク。
    /// 丸マーク＋タイトルをタップすると「1回消費」。「負けそう」ボタンはキャラ相談用に残す。
    @ViewBuilder
    private func promiseCard(_ behavior: BlockedBehavior) -> some View {
        let usage = viewModel.promiseUsage(for: behavior)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    withAnimation { viewModel.consumePromise(behavior) }
                } label: {
                    HStack(spacing: 12) {
                        ProgressCircle(
                            progress: usage.fraction,
                            size: 34,
                            tint: usage.exceeded ? AppColor.error : AppColor.warning,
                            showsCheckmarkWhenComplete: false
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

                            Text("\(usage.periodLabel) \(usage.used) / \(usage.limit)回")
                                .font(.caption2)
                                .foregroundStyle(usage.exceeded ? AppColor.error : AppColor.muted)
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

            Button {
                confrontTemptation()
            } label: {
                Text("負けそう")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.error)
        }
    }

    // MARK: - 3. みんなのざこ速報(プレースホルダ。フィード連携は別Step)

    private var zakoBulletinSection: some View {
        Section("みんなのざこ速報") {
            ZakoBulletinFeedView(items: viewModel.zakoBulletinItems)
        }
        .appCardRow()
    }

    // MARK: - helpers

    private func confrontTemptation() {
        Task {
            temptationMessage = await viewModel.confrontTemptation()
            isPresentingTemptationMessage = true
        }
    }

    /// App Intent「今日のルーティンを開く」(`OpenTodayRoutinesIntent`)が要求されていれば、
    /// 今日ぶんで未完了の先頭ルーティンへ遷移する。
    private func startPendingRoutineIfNeeded() {
        guard siriLaunchCoordinator.pendingOpenTodayRoutines else { return }
        siriLaunchCoordinator.pendingOpenTodayRoutines = false
        selectedRoutine = viewModel.firstPendingTodayRoutine()
    }

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
        for: [
            Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self,
            CharacterPreset.self, BlockedBehavior.self, TrustState.self,
            UserProfileFact.self, FreeTalkTopicProgress.self, DailyConversationState.self,
            EventProgress.self,
            RelationshipState.self,
        ],
        inMemory: true
    )
}
