import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = HomeViewModel()
    @State private var selectedRoutine: Routine?

    var body: some View {
        List {
            Section("今日のルーティン") {
                routineRow(title: "朝ルーティン", routine: viewModel.morningRoutine, buttonTitle: "朝ルーティン開始")
                routineRow(title: "夜ルーティン", routine: viewModel.nightRoutine, buttonTitle: "夜ルーティン開始")
            }

            Section {
                NavigationLink("ルーティン一覧・編集") {
                    RoutineListView()
                }
                NavigationLink("やらないことリスト") {
                    BlockedBehaviorListView()
                }
            }
        }
        .navigationTitle("メスガキルーティン")
        .navigationDestination(item: $selectedRoutine) { routine in
            RoutineSessionView(routine: routine)
        }
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
        }
    }

    @ViewBuilder
    private func routineRow(title: String, routine: Routine?, buttonTitle: String) -> some View {
        if let routine {
            VStack(alignment: .leading, spacing: 8) {
                Text(routine.title)
                    .font(.headline)
                Text("\(routine.orderedSteps.count)ステップ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(buttonTitle) {
                    selectedRoutine = routine
                }
                .buttonStyle(.borderedProminent)
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
