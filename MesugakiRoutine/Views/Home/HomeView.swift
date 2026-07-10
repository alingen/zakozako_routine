import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var selectedRoutine: Routine?
    @State private var editingRoutine: Routine?

    var body: some View {
        List {
            Section("今日のルーティン") {
                routineRow(title: "朝ルーティン", routine: viewModel.morningRoutine)
                routineRow(title: "夜ルーティン", routine: viewModel.nightRoutine)
            }

            Section {
                if viewModel.blockedBehaviors.isEmpty {
                    Text("登録されていません")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.blockedBehaviors, id: \.id) { behavior in
                        Text(behavior.title)
                    }
                }
            } header: {
                HStack {
                    Text("やらないことリスト")
                    Spacer()
                    NavigationLink {
                        BlockedBehaviorListView()
                    } label: {
                        Image(systemName: "pencil")
                    }
                }
            }
        }
        .navigationDestination(item: $selectedRoutine) { routine in
            RoutineSessionView(routine: routine)
        }
        .navigationDestination(item: $editingRoutine) { routine in
            RoutineEditView(routine: routine)
        }
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
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
