import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SiriLaunchCoordinator.self) private var siriLaunchCoordinator
    @State private var viewModel = HomeViewModel()
    @State private var selectedRoutine: Routine?
    @State private var editingRoutine: Routine?
    @State private var isPresentingTemptationPicker = false
    @State private var isPresentingTemptationMessage = false
    @State private var temptationMessage = ""
    @State private var isPresentingSiriHelp = false
    @State private var editingBehavior: BlockedBehavior?
    @State private var isPresentingProfile = false

    var body: some View {
        List {
            if !viewModel.homeComment.isEmpty {
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
                        Text(viewModel.homeComment)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                }
            }

            if viewModel.isListeningForVoiceCommand {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("🎙️ 「朝ルーティン」「夜ルーティン」など話しかけてください…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    isPresentingTemptationPicker = true
                } label: {
                    Text("負けそう")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .buttonBorderShape(.roundedRectangle)
                .listRowBackground(Color.clear)
            }

            Section {
                routineRow(title: "朝ルーティン", routine: viewModel.morningRoutine)
                routineRow(title: "夜ルーティン", routine: viewModel.nightRoutine)
            } header: {
                HStack {
                    Text("今日のルーティン")
                    Button {
                        isPresentingSiriHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                    }
                }
            }

            Section("やらないことリスト") {
                ForEach(viewModel.blockedBehaviors, id: \.id) { behavior in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(behavior.title)
                            if let subtitle = detailSubtitle(for: behavior) {
                                Text(subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { behavior.isActive },
                            set: { _ in viewModel.toggleBlockedBehavior(behavior) }
                        ))
                        .labelsHidden()
                        Button {
                            editingBehavior = behavior
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
                .onDelete { viewModel.deleteBlockedBehaviors(at: $0) }

                HStack {
                    TextField("追加する項目", text: $viewModel.newBlockedBehaviorTitle)
                    Button("追加") {
                        viewModel.addBlockedBehavior()
                    }
                    .disabled(viewModel.newBlockedBehaviorTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationDestination(item: $selectedRoutine) { routine in
            RoutineSessionView(routine: routine)
        }
        .navigationDestination(item: $editingRoutine) { routine in
            RoutineEditView(routine: routine)
        }
        .confirmationDialog("何に負けそう？", isPresented: $isPresentingTemptationPicker, titleVisibility: .visible) {
            ForEach(viewModel.blockedBehaviors.filter(\.isActive), id: \.id) { behavior in
                Button(behavior.title) {
                    confrontTemptation(behavior)
                }
            }
            Button("とにかく負けそう") {
                confrontTemptation(nil)
            }
            Button("キャンセル", role: .cancel) {}
        }
        .alert("小悪魔コーチより", isPresented: $isPresentingTemptationMessage) {
            Button("がんばる", role: .cancel) {}
        } message: {
            Text(temptationMessage)
        }
        .sheet(isPresented: $isPresentingSiriHelp) {
            SiriShortcutHelpView()
        }
        .sheet(isPresented: $isPresentingProfile) {
            CharacterProfileView()
        }
        .sheet(item: $editingBehavior) { behavior in
            BlockedBehaviorDetailView(behavior: behavior) { triggerText, alternativeAction, useTimeWindow, start, end in
                viewModel.updateBlockedBehaviorDetails(
                    behavior,
                    triggerText: triggerText,
                    alternativeAction: alternativeAction,
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
            triggerAutoListenIfNeeded()
            startPendingRoutineIfNeeded()
            Task { await viewModel.loadHomeComment() }
        }
        .onChange(of: siriLaunchCoordinator.shouldAutoListenOnNextHomeAppear) {
            triggerAutoListenIfNeeded()
        }
        .onChange(of: siriLaunchCoordinator.pendingRoutineTypeToStart) {
            startPendingRoutineIfNeeded()
        }
    }

    private func confrontTemptation(_ behavior: BlockedBehavior?) {
        Task {
            temptationMessage = await viewModel.confrontTemptation(behavior)
            isPresentingTemptationMessage = true
        }
    }

    /// Siriショートカット(zakozakoroutine:// URL)経由で開かれた時だけ、数秒間の音声コマンド受付を始める。
    /// 手動でアイコンをタップして開いた場合は発火しない。
    private func triggerAutoListenIfNeeded() {
        guard siriLaunchCoordinator.shouldAutoListenOnNextHomeAppear else { return }
        siriLaunchCoordinator.shouldAutoListenOnNextHomeAppear = false
        Task {
            if let routine = await viewModel.listenForRoutineVoiceCommand() {
                selectedRoutine = routine
            }
        }
    }

    /// App Intent(StartRoutineIntent)経由で「このルーティンを開始して」と指定されていれば、
    /// 該当ルーティンへ直接遷移する。音声認識は不要(Siriが既にどちらか判定済みのため)。
    private func startPendingRoutineIfNeeded() {
        guard let routineType = siriLaunchCoordinator.pendingRoutineTypeToStart else { return }
        siriLaunchCoordinator.pendingRoutineTypeToStart = nil
        switch routineType {
        case .morning: selectedRoutine = viewModel.morningRoutine
        case .night: selectedRoutine = viewModel.nightRoutine
        case .custom: break
        }
    }

    private func detailSubtitle(for behavior: BlockedBehavior) -> String? {
        var parts: [String] = []
        if let start = behavior.activeStartMinute, let end = behavior.activeEndMinute {
            parts.append("\(timeString(start))〜\(timeString(end))")
        }
        if !behavior.alternativeAction.isEmpty {
            parts.append("代替: \(behavior.alternativeAction)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ・ ")
    }

    private func timeString(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    @ViewBuilder
    private func routineRow(title: String, routine: Routine?) -> some View {
        if let routine {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.title)
                        .font(.headline)
                    Text("\(routine.orderedSteps.count)ステップ")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("開始") {
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
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        HomeView()
    }
    .environment(SiriLaunchCoordinator())
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self, CharacterPreset.self, BlockedBehavior.self], inMemory: true)
}
