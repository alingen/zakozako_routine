import SwiftUI

struct RoutineEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RoutineEditViewModel
    @State private var isPresentingDeleteConfirm = false

    private let isExisting: Bool

    init(routine: Routine?) {
        _viewModel = State(initialValue: RoutineEditViewModel(routine: routine))
        isExisting = routine != nil
    }

    var body: some View {
        Form {
            Section("ルーティン情報") {
                TextField("タイトル", text: $viewModel.title)
                    .onChange(of: viewModel.title) {
                        viewModel.save()
                    }
            }

            Section("アイコン") {
                iconGrid
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
                     ? "この時刻を過ぎてもルーティンが終わっていないと、通知でお知らせします。"
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

            if isExisting {
                Section {
                    Button("このルーティンを削除", role: .destructive) {
                        isPresentingDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(isExisting ? "ルーティン編集" : "ルーティン新規作成")
        .confirmationDialog("このルーティンを削除しますか？", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                viewModel.deleteRoutine()
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .task {
            viewModel.configure(context: modelContext)
        }
    }

    private var iconGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 6)
        return LazyVGrid(columns: columns, spacing: 10) {
            iconButton(nil, systemImage: "nosign", label: "なし")
            ForEach(RoutineIcon.all, id: \.self) { name in
                iconButton(name, systemImage: name, label: name)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func iconButton(_ name: String?, systemImage: String, label: String) -> some View {
        let selected = viewModel.iconName == name
        Button {
            viewModel.iconName = name
            viewModel.save()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .frame(width: 40, height: 40)
                .foregroundStyle(selected ? Color.white : AppColor.text)
                .background(selected ? AppColor.primary : AppColor.border.opacity(0.5), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    NavigationStack {
        RoutineEditView(routine: nil)
    }
    .modelContainer(for: [Routine.self, RoutineStep.self], inMemory: true)
}
