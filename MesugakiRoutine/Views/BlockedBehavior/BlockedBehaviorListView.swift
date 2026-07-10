import SwiftUI

struct BlockedBehaviorListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = BlockedBehaviorListViewModel()
    @State private var isPresentingNew = false

    var body: some View {
        List {
            Section("やらないことリスト") {
                if viewModel.behaviors.isEmpty {
                    Text("登録されていません")
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.behaviors) { behavior in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(behavior.title)
                                .font(.headline)
                                .strikethrough(!behavior.isActive)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { behavior.isActive },
                                set: { _ in viewModel.toggleActive(behavior) }
                            ))
                            .labelsHidden()
                        }
                        if !behavior.counterMessage.isEmpty {
                            Text(behavior.counterMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { viewModel.delete(at: $0) }
            }
        }
        .navigationTitle("やらないことリスト")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isPresentingNew = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingNew) {
            NavigationStack {
                Form {
                    Section("行動") {
                        TextField("タイトル (例: YouTubeをだらだら見る)", text: $viewModel.newTitle)
                        TextField("検知ワード (例: YouTube)", text: $viewModel.newTriggerText)
                    }
                    Section("キャラクターの声かけ") {
                        TextField("カウンターメッセージ", text: $viewModel.newCounterMessage, axis: .vertical)
                    }
                }
                .navigationTitle("新規追加")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("追加") {
                            viewModel.add()
                            isPresentingNew = false
                        }
                        .disabled(!viewModel.canAdd)
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("キャンセル") { isPresentingNew = false }
                    }
                }
            }
        }
        .task {
            viewModel.configure(context: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        BlockedBehaviorListView()
    }
    .modelContainer(for: [BlockedBehavior.self], inMemory: true)
}
