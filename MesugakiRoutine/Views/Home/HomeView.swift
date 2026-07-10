import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var selectedRoutine: Routine?
    @State private var editingRoutine: Routine?
    @State private var isPresentingTemptationPicker = false
    @State private var isPresentingTemptationMessage = false
    @State private var temptationMessage = ""

    var body: some View {
        List {
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

            Section("今日のルーティン") {
                routineRow(title: "朝ルーティン", routine: viewModel.morningRoutine)
                routineRow(title: "夜ルーティン", routine: viewModel.nightRoutine)
            }

            Section("やらないことリスト") {
                ForEach(viewModel.blockedBehaviors, id: \.id) { behavior in
                    Toggle(isOn: Binding(
                        get: { behavior.isActive },
                        set: { _ in viewModel.toggleBlockedBehavior(behavior) }
                    )) {
                        Text(behavior.title)
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
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
        }
    }

    private func confrontTemptation(_ behavior: BlockedBehavior?) {
        Task {
            temptationMessage = await viewModel.confrontTemptation(behavior)
            isPresentingTemptationMessage = true
        }
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
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self, CharacterPreset.self, BlockedBehavior.self], inMemory: true)
}
