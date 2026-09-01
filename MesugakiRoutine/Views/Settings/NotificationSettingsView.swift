import SwiftUI

/// 「通知」設定画面。全ルーティン共通で、サボり通知の有効/無効と
/// 「各ルーティンの開始予定時刻から何分後に通知するか」を設定する。
struct NotificationSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = NotificationSettingsViewModel()

    private static let delayOptions = [10, 15, 30, 45, 60, 90, 120]

    var body: some View {
        List {
            if viewModel.isSystemAuthorizationDenied {
                Section {
                    Text("通知が許可されていません。設定アプリからこのアプリの通知を許可してください。")
                        .font(.footnote)
                        .foregroundStyle(AppColor.error)
                }
            }

            Section {
                Toggle(
                    "サボり通知",
                    isOn: Binding(
                        get: { viewModel.notificationsEnabled },
                        set: { viewModel.setNotificationsEnabled($0) }
                    )
                )
                if viewModel.notificationsEnabled {
                    Picker(
                        "通知タイミング",
                        selection: Binding(
                            get: { viewModel.delayMinutes },
                            set: { viewModel.setDelayMinutes($0) }
                        )
                    ) {
                        ForEach(Self.delayOptions, id: \.self) { minutes in
                            Text("\(minutes)分後").tag(minutes)
                        }
                    }
                }
            } footer: {
                Text("開始予定時刻から指定した時間が経ってもそのルーティンが終わっていない場合に通知します。")
            }

            if !viewModel.routines.isEmpty {
                Section("対象ルーティン") {
                    ForEach(viewModel.routines) { routine in
                        HStack {
                            Text(routine.title)
                            Spacer()
                            if let minute = routine.scheduledStartMinute {
                                Text(timeString(fromMinutes: minute))
                                    .foregroundStyle(AppColor.muted)
                            } else {
                                Text("通知オフ")
                                    .font(.footnote)
                                    .foregroundStyle(AppColor.muted)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("通知")
        .task {
            viewModel.configure(context: modelContext)
        }
        .onAppear {
            viewModel.reload()
        }
    }

    private func timeString(fromMinutes minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

#Preview {
    NavigationStack {
        NotificationSettingsView()
    }
    .modelContainer(for: [Routine.self, RoutineStep.self, RoutineSession.self, RoutineEvent.self], inMemory: true)
}
