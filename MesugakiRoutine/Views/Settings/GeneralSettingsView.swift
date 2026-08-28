import SwiftUI
import SwiftData

/// 「一般」設定画面。
struct GeneralSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var uiMode: AppUIMode = AppSettingsStore.uiMode
    @State private var userNickname: String = AppSettingsStore.userNickname
    @State private var trustPoints: Int = 0
    @State private var trustStage: Int = 1
    @State private var dailyConversationIndex: Int = 0
    @State private var userFacts: [(key: String, value: String)] = []
    @State private var eventRows: [EventDebugRow] = []
    @State private var metricsSummary: String = ""

    private struct EventDebugRow: Identifiable {
        let id: String
        let title: String
        let condition: String
        let status: String
    }

    private var trustRepository: TrustRepository { TrustRepository(context: modelContext) }
    private var dailyConversationStateRepository: DailyConversationStateRepository {
        DailyConversationStateRepository(context: modelContext)
    }
    private var userProfileFactRepository: UserProfileFactRepository {
        UserProfileFactRepository(context: modelContext)
    }

    var body: some View {
        List {
            Section {
                TextField("例: おにいさん、おねえさん", text: $userNickname)
                    .onChange(of: userNickname) {
                        AppSettingsStore.userNickname = userNickname
                    }
            } header: {
                Text("呼び名")
            } footer: {
                Text("キャラクターがあなたを呼ぶ時の呼び名です。空欄なら特に呼びかけません。")
            }

            Section {
                Picker(selection: $uiMode) {
                    ForEach(AppUIMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
                .onChange(of: uiMode) {
                    AppSettingsStore.uiMode = uiMode
                }
            } header: {
                Text("モード")
            } footer: {
                Text("\(uiMode.description)\n見た目の切り替えは準備中で、現在はまだ反映されません。")
            }

            Section {
                Text("現在: ステージ\(trustStage)(\(trustPoints)pt)")
                    .font(.subheadline)
                Button("低ステージにする") {
                    setTrustPoints(0)
                }
                Button("中ステージにする") {
                    setTrustPoints(TrustStage.pointsPerStage * 2)
                }
                Button("高ステージにする") {
                    setTrustPoints(TrustStage.pointsPerStage * 5)
                }
            } header: {
                Text("信頼度(デバッグ用)")
            } footer: {
                Text("信頼度ステージによる応答の変化を確認するためのテスト用ボタンです。ここでの切り替えは、そのステージのフリートーク話題が完了しているかに関わらず強制的に反映されます。")
            }

            Section {
                Text("次に再生する会話: Day \(dailyConversationIndex + 1)")
                    .font(.subheadline)
                Button("最初(Day 1)に戻す") {
                    dailyConversationStateRepository.setIndex(0)
                    dailyConversationIndex = 0
                }
            } header: {
                Text("今日の会話(デバッグ用)")
            } footer: {
                Text("「今日の会話」はルーティン完了後に開始できます。ここでは進行度を最初に戻して、Day1から再確認できます。")
            }

            Section {
                Text(metricsSummary.isEmpty ? "—" : metricsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(eventRows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(row.title).font(.subheadline)
                            Spacer()
                            Text(row.status).font(.caption).foregroundStyle(.secondary)
                        }
                        Text("条件: \(row.condition)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Button("やらないこと回数を +1") {
                    AppSettingsStore.blockedBehaviorProtectedCount += 1
                    refreshEventDebug()
                }
                Button("継続日数を +1") {
                    extendStreakByOneDay()
                    refreshEventDebug()
                }
                Button("継続日数をリセット", role: .destructive) {
                    AppDependencies(context: modelContext).sessionRepository.debugRemoveSyntheticSessions()
                    refreshEventDebug()
                }
                Button("イベント進行をリセット", role: .destructive) {
                    let deps = AppDependencies(context: modelContext)
                    deps.eventProgressRepository.resetAll()
                    deps.relationshipRepository.setPhase(0)
                    refreshEventDebug()
                }
                Button("関係性フェーズを +1") {
                    let deps = AppDependencies(context: modelContext)
                    deps.relationshipRepository.setPhase(deps.relationshipRepository.phase + 1)
                    refreshEventDebug()
                }
            } header: {
                Text("イベント(デバッグ用)")
            } footer: {
                Text("信頼度・継続日数・やらないこと回数などの条件を満たすとイベントが「解放」されます。解放後は今日の会話の後やホーム画面から開始できます。「継続日数を +1」は前の日に完了記録を1件追加します。")
            }

            Section {
                if userFacts.isEmpty {
                    Text("まだ保存された情報はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(userFacts, id: \.key) { fact in
                        HStack {
                            Text(fact.key).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(fact.value).font(.subheadline)
                        }
                    }
                }
                Button("すべて消す", role: .destructive) {
                    for fact in userProfileFactRepository.fetchAll() {
                        userProfileFactRepository.delete(fact)
                    }
                    reloadUserFacts()
                }
                .disabled(userFacts.isEmpty)
            } header: {
                Text("保存されたユーザー情報(デバッグ用)")
            } footer: {
                Text("会話の選択肢などから保存された情報です。別の会話で `{{fact:キー}}` として参照されます。")
            }
        }
        .navigationTitle("一般")
        .task {
            trustPoints = trustRepository.points
            trustStage = trustRepository.stage
            dailyConversationIndex = dailyConversationStateRepository.currentIndex
            reloadUserFacts()
            refreshEventDebug()
        }
    }

    private func reloadUserFacts() {
        userFacts = userProfileFactRepository.fetchAll().map { ($0.key, $0.value) }
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
        // 今日が未達成なら昨日を起点に、遡って最初の「未達成日」を埋める。
        var cursor = completedDays.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while completedDays.contains(cursor) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        let routineId = deps.routineRepository.fetch(type: .morning).first?.id
            ?? deps.routineRepository.fetchAll().first?.id
            ?? UUID()
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: cursor) ?? cursor
        deps.sessionRepository.debugInsertCompletedSession(routineId: routineId, completedAt: noon)
    }

    private func refreshEventDebug() {
        let deps = AppDependencies(context: modelContext)
        deps.eventUnlockService.refreshUnlocks()
        let metrics = deps.progressMetricsProvider.current()
        metricsSummary = "信頼度\(metrics.trustPoints)pt / 継続\(metrics.streakDays)日 / やらないこと\(metrics.blockedProtectedCount)回 / 卒業\(metrics.masteredCount)個 / 関係Phase\(metrics.relationshipPhase)"
        eventRows = deps.eventCatalog.allEvents.map { event in
            let progress = deps.eventProgressRepository.progress(for: event.eventId)
            let status: String
            if progress?.isCompleted == true {
                status = "完了"
            } else if progress?.isUnlocked == true {
                status = "解放済み(未完了)"
            } else {
                status = "未解放"
            }
            return EventDebugRow(
                id: event.eventId,
                title: event.title,
                condition: event.unlockConditions.summary,
                status: status
            )
        }
    }

    private func setTrustPoints(_ points: Int) {
        trustRepository.setPoints(points)
        trustPoints = points
        trustStage = trustRepository.stage
    }
}

#Preview {
    NavigationStack {
        GeneralSettingsView()
    }
}
