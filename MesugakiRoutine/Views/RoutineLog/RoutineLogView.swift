import SwiftUI

struct RoutineLogView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = RoutineLogViewModel()

    var body: some View {
        List {
            if viewModel.logs.isEmpty {
                Text("まだログがありません")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.logs) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(log.title)
                                .font(.subheadline.bold())
                            Spacer()
                            Text(log.date, style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if !log.subtitle.isEmpty {
                            Text(log.subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("記録")
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
        RoutineLogView()
    }
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self], inMemory: true)
}
