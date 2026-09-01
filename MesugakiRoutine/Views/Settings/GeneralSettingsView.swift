import SwiftUI
import SwiftData

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var userName: String = AppSettingsStore.userName
    @State private var userHonorific: UserHonorific = AppSettingsStore.userHonorific
    @State private var routineDebugRows: [RoutineDebugRow] = []

    private struct RoutineDebugRow: Identifiable {
        let id: UUID
        let title: String
        let detail: String
    }

    private var previewName: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? userHonorific.displayName : name + userHonorific.displayName
    }

    var body: some View {
        List {
            Section {
                TextField("例: だいすけ", text: $userName)
                    .onChange(of: userName) { AppSettingsStore.userName = userName }
                Picker("よびかた", selection: $userHonorific) {
                    ForEach(UserHonorific.allCases) { honorific in
                        Text(honorific.displayName).tag(honorific)
                    }
                }
                .onChange(of: userHonorific) { AppSettingsStore.userHonorific = userHonorific }
            } header: {
                Text("あなたのこと")
            } footer: {
                Text("みんなのざこ速報の表示に使います(例: 「\(previewName)」)。")
            }

            Section {
                Button("約束を1日巻き戻す(自動判定テスト)") {
                    AppDependencies(context: modelContext).blockedBehaviorRepository.debugAgePromiseByOneDay()
                }
                Button("先頭の約束を昨日達成扱いにする") {
                    let deps = AppDependencies(context: modelContext)
                    guard let routine = deps.routineRepository.fetchAll().first else { return }
                    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
                    for _ in 0..<routine.targetCount {
                        deps.routineRepository.debugInsertProgress(routine, on: yesterday)
                    }
                    reloadRoutineDebug()
                }
            } header: {
                Text("デバッグ")
            }

            Section {
                if routineDebugRows.isEmpty {
                    Text("約束がありません")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)
                } else {
                    ForEach(routineDebugRows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.subheadline)
                            Text(row.detail).font(.caption2).foregroundStyle(AppColor.muted)
                        }
                    }
                }
            } header: {
                Text("約束の進捗・連続達成(デバッグ用)")
            }
        }
        .navigationTitle("一般")
        .task {
            reloadRoutineDebug()
        }
    }

    private func reloadRoutineDebug() {
        let deps = AppDependencies(context: modelContext)
        routineDebugRows = deps.routineRepository.fetchAll().map { routine in
            let progress = routine.todayProgress()
            let streak = RoutineStreak.currentStreak(routine: routine)
            let pct = Int((progress.fraction * 100).rounded())
            return RoutineDebugRow(
                id: routine.id,
                title: routine.title,
                detail: "\(routine.period.currentUnitLabel) \(progress.done)/\(progress.target)回 (\(pct)%) ・ \(streak)日連続"
            )
        }
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
