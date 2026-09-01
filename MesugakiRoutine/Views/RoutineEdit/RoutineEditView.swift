import SwiftUI

struct RoutineEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: RoutineEditViewModel
    @State private var isPresentingDeleteConfirm = false
    @State private var isPresentingIconPicker = false

    private let isExisting: Bool

    init(routine: Routine?) {
        _viewModel = State(initialValue: RoutineEditViewModel(routine: routine))
        isExisting = routine != nil
    }

    var body: some View {
        Form {
            Section("約束") {
                TextField("タイトル", text: $viewModel.title)
                    .onChange(of: viewModel.title) { viewModel.save() }
            }

            Section("アイコン") {
                Button {
                    isPresentingIconPicker = true
                } label: {
                    HStack {
                        Text("アイコン")
                            .foregroundStyle(AppColor.text)
                        Spacer()
                        if let icon = viewModel.iconName {
                            Image(systemName: icon)
                                .foregroundStyle(AppColor.primary)
                        } else {
                            Text("なし")
                                .foregroundStyle(AppColor.muted)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColor.muted)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Section {
                Picker("ペース", selection: $viewModel.period) {
                    ForEach(HabitPeriod.allCases) { period in
                        Text(period.pickerLabel).tag(period)
                    }
                }
                .onChange(of: viewModel.period) { viewModel.save() }

                Stepper("\(viewModel.period.pickerLabel) \(viewModel.targetCount)回", value: $viewModel.targetCount, in: 1...50)
                    .onChange(of: viewModel.targetCount) { viewModel.save() }
            } header: {
                Text("回数")
            } footer: {
                Text("この期間のあいだに、円をタップしてこの回数をこなすと「達成」です。")
            }

            if viewModel.canSelectWeekdays {
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
                        Text("続けるコツは毎日やることです")
                            .font(.footnote)
                            .foregroundStyle(AppColor.muted)
                    }
                } header: {
                    Text("対象曜日")
                }
            }

            Section {
                Toggle("指定時刻に通知する", isOn: $viewModel.notifyAtScheduledTime)
                    .onChange(of: viewModel.notifyAtScheduledTime) { viewModel.save() }
                if viewModel.notifyAtScheduledTime {
                    DatePicker("通知時刻", selection: $viewModel.scheduledStartTime, displayedComponents: .hourAndMinute)
                        .onChange(of: viewModel.scheduledStartTime) { viewModel.save() }
                }
            } header: {
                Text("通知")
            } footer: {
                Text(viewModel.notifyAtScheduledTime
                     ? "この時刻を過ぎても達成していないと、通知でお知らせします。"
                     : "この約束の通知はオフです。")
            }

            if isExisting {
                Section {
                    Button("この約束を削除", role: .destructive) {
                        isPresentingDeleteConfirm = true
                    }
                }
            }
        }
        .navigationTitle(isExisting ? "約束を編集" : "約束を追加")
        .confirmationDialog("この約束を削除しますか？", isPresented: $isPresentingDeleteConfirm, titleVisibility: .visible) {
            Button("削除する", role: .destructive) {
                viewModel.deleteRoutine()
                dismiss()
            }
            Button("キャンセル", role: .cancel) {}
        }
        .sheet(isPresented: $isPresentingIconPicker) {
            IconPickerView(selected: viewModel.iconName) { name in
                viewModel.iconName = name
                viewModel.save()
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
    .modelContainer(for: [Routine.self, BlockedBehavior.self], inMemory: true)
}
