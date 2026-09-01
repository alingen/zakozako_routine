import SwiftUI

struct RoutineListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RoutineListViewModel()
    @State private var isPresentingNew = false

    var body: some View {
        List {
            ForEach(viewModel.routines) { routine in
                NavigationLink {
                    RoutineEditView(routine: routine)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(routine.title).font(.headline)
                            if !routine.isActive {
                                Text("無効")
                                    .font(.caption2)
                                    .foregroundStyle(AppColor.muted)
                            }
                        }
                        Text("\(routine.type.displayName) ・ \(routine.orderedSteps.count)ステップ")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    viewModel.delete(viewModel.routines[index])
                }
            }
        }
        .navigationTitle("ルーティン一覧")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNew, onDismiss: { viewModel.reload() }) {
            NavigationStack {
                RoutineEditView(routine: nil)
            }
        }
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
        }
    }
}

#Preview {
    NavigationStack {
        RoutineListView()
    }
    .modelContainer(for: [Routine.self, RoutineStep.self], inMemory: true)
}
