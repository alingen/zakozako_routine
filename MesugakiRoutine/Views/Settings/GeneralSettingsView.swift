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

    /// フッターに出す表示名プレビュー。
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
                Button("継続日数を +1") {
                    extendStreakByOneDay()
                    reloadRoutineDebug()
                }
                Button("継続日数をリセット", role: .destructive) {
                    AppDependencies(context: modelContext).sessionRepository.debugRemoveSyntheticSessions()
                    reloadRoutineDebug()
                }
            } header: {
                Text("デバッグ")
            }

            Section {
                if routineDebugRows.isEmpty {
                    Text("ルーティンがありません")
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
                Text("ルーティンの今日の進捗・連続達成(デバッグ用)")
            }
        }
        .navigationTitle("一般")
        .task {
            reloadRoutineDebug()
        }
    }

    private func reloadRoutineDebug() {
        let deps = AppDependencies(context: modelContext)
        let sessions = deps.sessionRepository.fetchAllSessions()
        routineDebugRows = deps.routineRepository.fetchAll().map { routine in
            let progress = RoutineProgressCalculator.todayProgress(routine: routine, sessions: sessions)
            let streak = RoutineStreakCalculator.currentStreak(routine: routine, sessions: sessions)
            let pct = Int((progress.fraction * 100).rounded())
            let steps = progress.totalSteps > 0 ? " (\(progress.completedSteps)/\(progress.totalSteps)ステップ)" : ""
            return RoutineDebugRow(
                id: routine.id,
                title: routine.title,
                detail: "今日の進捗 \(pct)%\(steps) ・ \(streak)回連続"
            )
        }
    }

    /// 現在の連続達成日数のちょうど1つ手前の日に、完了扱いのダミーセッションを入れて継続日数を +1 する。
    private func extendStreakByOneDay() {
        let deps = AppDependencies(context: modelContext)
        let calendar = Calendar.current
        let sessions = deps.sessionRepository.fetchAllSessions()
        let completedDays = Set(
            sessions
                .filter { $0.status == .completed }
                .compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) }
        )
        let today = calendar.startOfDay(for: .now)
        var cursor = completedDays.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while completedDays.contains(cursor) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        let routineId = deps.routineRepository.fetchAll().first?.id ?? UUID()
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: cursor) ?? cursor
        deps.sessionRepository.debugInsertCompletedSession(routineId: routineId, completedAt: noon)
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
