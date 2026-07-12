import SwiftUI

/// 「通知」設定画面。ルーティンごとに、サボり通知の有効/無効と時刻を設定する。
struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NotificationSettingsViewModel()

    var body: some View {
        List {
            if viewModel.isSystemAuthorizationDenied {
                Section {
                    Text("通知が許可されていません。設定アプリからこのアプリの通知を許可してください。")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let morningRoutine = viewModel.morningRoutine {
                reminderSection(
                    title: morningRoutine.title,
                    isEnabled: Binding(
                        get: { viewModel.morningReminderEnabled },
                        set: { viewModel.setMorningReminder(enabled: $0) }
                    ),
                    time: Binding(
                        get: { viewModel.morningReminderTime },
                        set: { viewModel.setMorningReminderTime($0) }
                    )
                )
            }

            if let nightRoutine = viewModel.nightRoutine {
                reminderSection(
                    title: nightRoutine.title,
                    isEnabled: Binding(
                        get: { viewModel.nightReminderEnabled },
                        set: { viewModel.setNightReminder(enabled: $0) }
                    ),
                    time: Binding(
                        get: { viewModel.nightReminderTime },
                        set: { viewModel.setNightReminderTime($0) }
                    )
                )
            }
        }
        .navigationTitle("通知")
        .task {
            viewModel.configure(context: modelContext)
        }
    }

    private func reminderSection(title: String, isEnabled: Binding<Bool>, time: Binding<Date>) -> some View {
        Section {
            Toggle("サボり通知", isOn: isEnabled)
            if isEnabled.wrappedValue {
                DatePicker("通知時刻", selection: time, displayedComponents: .hourAndMinute)
            }
        } header: {
            Text(title)
        } footer: {
            Text("この時刻までに\(title)が終わっていない場合に通知します。")
        }
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self], inMemory: true)
}
