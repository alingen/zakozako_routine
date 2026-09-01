import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @State private var viewModel = HomeViewModel()
    @State private var selectedRoutine: Routine?
    @State private var editingRoutine: Routine?
    @State private var isPresentingTemptationMessage = false
    @State private var temptationMessage = ""
    @State private var editingBehavior: BlockedBehavior?
    @State private var isPresentingProfile = false
    @State private var isPresentingCheckIn = false
    @State private var presentedEvent: EventDefinition?

    var body: some View {
        List {
            if viewModel.isLoadingHomeComment || !viewModel.homeComment.isEmpty {
                Section {
                    HStack(alignment: .top, spacing: 12) {
                        Image("CharacterIcon")
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .onTapGesture {
                                isPresentingProfile = true
                            }
                        if viewModel.isLoadingHomeComment {
                            TypingIndicatorView()
                                .frame(height: 22)
                        } else {
                            Text(viewModel.homeComment)
                                .font(.subheadline)
                                .foregroundStyle(AppColor.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .appCardRow()
            }

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

            Section {
                Button {
                    confrontTemptation()
                } label: {
                    Text("負けそう")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(AppColor.error)
                .buttonBorderShape(.roundedRectangle)
                .listRowBackground(Color.clear)
            }

            Section("今日のルーティン") {
                routineRow(title: "朝ルーティン", routine: viewModel.morningRoutine)
                routineRow(title: "夜ルーティン", routine: viewModel.nightRoutine)
            }
            .appCardRow()

            Section("やらないこと") {
                if let behavior = viewModel.currentBehavior {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(behavior.title)
                                    .font(.headline)
                                    .foregroundStyle(AppColor.text)
                                if !behavior.reason.isEmpty {
                                    Text("理由: \(behavior.reason)")
                                        .font(.caption)
                                        .foregroundStyle(AppColor.muted)
                                }
                                if !behavior.alternativeAction.isEmpty {
                                    Text("代替行動: \(behavior.alternativeAction)")
                                        .font(.caption)
                                        .foregroundStyle(AppColor.muted)
                                }
                            }
                            Spacer()
                            Button {
                                editingBehavior = behavior
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(AppColor.muted)
                        }
                        ProgressView(
                            value: Double(min(behavior.currentStreakDays, BlockedBehavior.masteryStreakDays)),
                            total: Double(BlockedBehavior.masteryStreakDays)
                        )
                        Text("\(behavior.currentStreakDays)/\(BlockedBehavior.masteryStreakDays)日達成")
                            .font(.caption2)
                            .foregroundStyle(AppColor.muted)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("やらないこと(例: YouTubeを見ない)", text: $viewModel.newBlockedBehaviorTitle)
                        TextField("理由(例: 仕事をさぼらないため)", text: $viewModel.newBlockedBehaviorReason)
                        TextField("代替行動(例: 音楽をかける)", text: $viewModel.newBlockedBehaviorAlternativeAction)
                        Button("追加") {
                            viewModel.addBlockedBehavior()
                        }
                        .disabled(viewModel.newBlockedBehaviorTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }

                if !viewModel.masteredBehaviors.isEmpty {
                    DisclosureGroup("卒業した習慣(\(viewModel.masteredBehaviors.count))") {
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
        .appScreenBackground()
        .navigationDestination(item: $selectedRoutine) { routine in
            RoutineSessionView(routine: routine)
        }
        .navigationDestination(item: $editingRoutine) { routine in
            RoutineEditView(routine: routine)
        }
        .alert("小悪魔コーチより", isPresented: $isPresentingTemptationMessage) {
            Button("がんばる", role: .cancel) {}
        } message: {
            Text(temptationMessage)
        }
        .alert(
            checkInAlertTitle,
            isPresented: $isPresentingCheckIn
        ) {
            Button("まもれた！") { viewModel.answerCheckIn(protected: true) }
            Button("まもれなかった…", role: .destructive) { viewModel.answerCheckIn(protected: false) }
        }
        .sheet(isPresented: $isPresentingProfile) {
            CharacterProfileView()
        }
        .fullScreenCover(item: $presentedEvent, onDismiss: { viewModel.reload() }) { event in
            NavigationStack {
                EventPlayerView(event: event)
            }
        }
        .sheet(item: $editingBehavior) { behavior in
            BlockedBehaviorDetailView(behavior: behavior) { reason, alternativeAction, triggerText, useTimeWindow, start, end in
                viewModel.updateBlockedBehaviorDetails(
                    behavior,
                    reason: reason,
                    alternativeAction: alternativeAction,
                    triggerText: triggerText,
                    useTimeWindow: useTimeWindow,
                    startTime: start,
                    endTime: end
                )
            }
        }
        .task {
            viewModel.configure(context: modelContext)
            await viewModel.loadHomeComment()
        }
        .onAppear {
            viewModel.reload()
            startPendingRoutineIfNeeded()
            triggerCheckInIfNeeded()
            Task { await viewModel.loadHomeComment() }
        }
        .onChange(of: siriLaunchCoordinator.pendingRoutineTypeToStart) {
            startPendingRoutineIfNeeded()
        }
    }

    private var checkInAlertTitle: String {
        guard let title = viewModel.pendingCheckInBehavior?.title else { return "" }
        return "昨日の「\(title)」は守れた？"
    }

    private func confrontTemptation() {
        Task {
            temptationMessage = await viewModel.confrontTemptation()
            isPresentingTemptationMessage = true
        }
    }

    /// 前日分の「まもれた/まもれなかった」がまだ未記録なら、確認アラートを出す。
    private func triggerCheckInIfNeeded() {
        guard viewModel.pendingCheckInBehavior != nil else { return }
        isPresentingCheckIn = true
    }

    /// App Intent(StartRoutineIntent)経由で「このルーティンを開始して」と指定されていれば、
    /// 該当ルーティンへ直接遷移する。
    private func startPendingRoutineIfNeeded() {
        guard let routineType = siriLaunchCoordinator.pendingRoutineTypeToStart else { return }
        siriLaunchCoordinator.pendingRoutineTypeToStart = nil
        switch routineType {
        case .morning: selectedRoutine = viewModel.morningRoutine
        case .night: selectedRoutine = viewModel.nightRoutine
        case .custom: break
        }
    }

    @ViewBuilder
    private func routineRow(title: String, routine: Routine?) -> some View {
        if let routine {
            let inProgressStep = viewModel.inProgressStepTitle(for: routine)
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.title)
                        .font(.headline)
                        .foregroundStyle(AppColor.text)
                    if let inProgressStep {
                        Text("\(inProgressStep)まで進行中")
                            .font(.caption)
                            .foregroundStyle(AppColor.warning)
                    } else {
                        Text("\(routine.orderedSteps.count)ステップ")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }
                }
                Spacer()
                Button(inProgressStep != nil ? "再開" : "開始") {
                    selectedRoutine = routine
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle)

                Button {
                    editingRoutine = routine
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
            }
            .padding(.vertical, 4)
        } else {
            Text("\(title)は未登録です")
                .foregroundStyle(AppColor.muted)
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
            Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self,
            CharacterPreset.self, BlockedBehavior.self, TrustState.self,
            UserProfileFact.self, FreeTalkTopicProgress.self, DailyConversationState.self,
            EventProgress.self,
            RelationshipState.self,
        ],
        inMemory: true
    )
}
