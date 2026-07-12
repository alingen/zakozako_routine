import SwiftUI

struct RoutineEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RoutineEditViewModel

    init(routine: Routine?) {
        _viewModel = State(initialValue: RoutineEditViewModel(routine: routine))
    }

    var body: some View {
        Form {
            Section("ルーティン情報") {
                TextField("タイトル", text: $viewModel.title)
                Picker("種別", selection: $viewModel.type) {
                    ForEach(RoutineType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                DatePicker("開始予定時間", selection: $viewModel.scheduledStartTime, displayedComponents: .hourAndMinute)
            }

            Section {
                HStack {
                    ForEach(Weekday.allCases) { weekday in
                        Button {
                            viewModel.toggleWeekday(weekday)
                        } label: {
                            Text(weekday.shortLabel)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    viewModel.selectedWeekdays.contains(weekday.rawValue)
                                        ? Color.accentColor
                                        : Color(.systemGray5)
                                )
                                .foregroundStyle(
                                    viewModel.selectedWeekdays.contains(weekday.rawValue) ? .white : .primary
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)

                if viewModel.showEveryDayHint {
                    Text("継続するためにおすすめは毎日やることです")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("対象曜日")
            }

            Section("ステップ") {
                ForEach(viewModel.steps) { step in
                    TextField(
                        "ステップ名",
                        text: Binding(
                            get: { step.title },
                            set: { viewModel.renameStep(step, newTitle: $0) }
                        )
                    )
                }
                .onDelete { viewModel.deleteSteps(at: $0) }
                .onMove { viewModel.moveSteps(from: $0, to: $1) }

                HStack {
                    TextField("新しいステップを追加", text: $viewModel.newStepTitle)
                    Button("追加") {
                        viewModel.addStep()
                    }
                    .disabled(viewModel.newStepTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .navigationTitle(viewModel.routine == nil ? "ルーティン新規作成" : "ルーティン編集")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("保存") {
                    viewModel.save()
                    dismiss()
                }
                .disabled(!viewModel.canSave)
            }
        }
        .task {
            viewModel.configure(context: modelContext)
        }
    }
}

#Preview {
    NavigationStack {
        RoutineEditView(routine: nil)
    }
    .modelContainer(for: [Routine.self, RoutineStep.self], inMemory: true)
}
