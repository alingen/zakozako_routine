import SwiftUI

struct RoutineEditView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: RoutineEditViewModel

    init(routine: Routine?) {
        _viewModel = State(initialValue: RoutineEditViewModel(routine: routine))
    }

    var body: some View {
        Form {
            Section("ルーティン情報") {
                TextField("タイトル", text: $viewModel.title)
                    .onChange(of: viewModel.title) {
                        viewModel.save()
                    }
            }

            Section {
                Toggle("指定時刻に通知する", isOn: $viewModel.notifyAtScheduledTime)
                    .onChange(of: viewModel.notifyAtScheduledTime) {
                        viewModel.save()
                    }
                if viewModel.notifyAtScheduledTime {
                    DatePicker("通知時刻", selection: $viewModel.scheduledStartTime, displayedComponents: .hourAndMinute)
                        .onChange(of: viewModel.scheduledStartTime) {
                            viewModel.save()
                        }
                }
            } header: {
                Text("通知")
            } footer: {
                Text(viewModel.notifyAtScheduledTime
                     ? "この時刻を過ぎてもルーティンが終わっていないと、小悪魔コーチがサボりを指摘します。"
                     : "このルーティンの通知はオフです。")
            }

            Section {
                HStack {
                    ForEach(Weekday.allCases) { weekday in
                        Button {
                            viewModel.toggleWeekday(weekday)
                            viewModel.save()
                        } label: {
                            Text(weekday.shortLabel)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                                .background(
                                    viewModel.selectedWeekdays.contains(weekday.rawValue)
                                        ? AppColor.primary
                                        : AppColor.border
                                )
                                .foregroundStyle(
                                    viewModel.selectedWeekdays.contains(weekday.rawValue) ? .white : AppColor.text
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
                        .foregroundStyle(AppColor.muted)
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
