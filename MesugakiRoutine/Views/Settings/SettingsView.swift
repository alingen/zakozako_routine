import SwiftData
import SwiftUI

/// 設定タブのトップ画面。設定項目の一覧から各設定画面へ遷移する。
struct SettingsView: View {
    var body: some View {
        List {
            NavigationLink("一般") {
                GeneralSettingsView()
            }
            NavigationLink("通知") {
                NotificationSettingsView()
            }
#if DEBUG
            NavigationLink {
                DebugSettingsView()
            } label: {
                Label("デバッグ", systemImage: "hammer.fill")
            }
#endif
        }
        .navigationTitle("設定")
    }
}

#if DEBUG
/// 開発中の進行確認に使う値と操作をまとめた専用画面。
private struct DebugSettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var cumulativeAchievementDays = 0
    @State private var continuousAchievementDays = 0
    @State private var actualContinuousAchievementDays = 0
    @State private var isContinuousOverrideEnabled = false
    @State private var trust = 0
    @State private var relationshipPhase = 0
    @State private var feedbackMessage: String?
    @State private var feedbackIsError = false
    @State private var routineDebugRows: [RoutineDebugRow] = []

    private struct RoutineDebugRow: Identifiable {
        let id: UUID
        let title: String
        let detail: String
    }

    var body: some View {
        List {
            Section {
                numberField("累積達成日数", value: $cumulativeAchievementDays)

                Toggle("連続達成日数を上書き", isOn: $isContinuousOverrideEnabled)
                if isContinuousOverrideEnabled {
                    numberField("連続達成日数", value: $continuousAchievementDays)
                } else {
                    LabeledContent("連続達成日数") {
                        Text("\(actualContinuousAchievementDays)日（実データ）")
                            .foregroundStyle(AppColor.muted)
                    }
                }

                numberField("信頼度", value: $trust)
                numberField("関係フェーズ", value: $relationshipPhase)
            } header: {
                Text("ストーリー進行値")
            } footer: {
                Text("保存するとストーリーの解放条件を再評価します。連続達成日数の上書きをオフにすると、約束の実データから算出した値を使います。")
            }

            Section {
                Button("保存して反映") {
                    saveProgressValues()
                }
                .frame(maxWidth: .infinity)

                if let feedbackMessage {
                    Label(
                        feedbackMessage,
                        systemImage: feedbackIsError
                            ? "exclamationmark.triangle.fill"
                            : "checkmark.circle.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(feedbackIsError ? AppColor.warning : AppColor.success)
                }
            }

            Section("日付・進捗操作") {
                Button("約束を1日巻き戻す（自動判定テスト）") {
                    AppDependencies(context: modelContext)
                        .blockedBehaviorRepository
                        .debugAgePromiseByOneDay()
                    reload()
                }

                Button("先頭の約束を昨日達成扱いにする") {
                    let dependencies = AppDependencies(context: modelContext)
                    guard let routine = dependencies.routineRepository.fetchAll().first else {
                        return
                    }
                    let yesterday = Calendar.current.date(
                        byAdding: .day,
                        value: -1,
                        to: .now
                    ) ?? .now
                    for _ in 0..<routine.targetCount {
                        dependencies.routineRepository.debugInsertProgress(
                            routine,
                            on: yesterday
                        )
                    }
                    reload()
                }
            }

            Section("約束の進捗・連続達成") {
                if routineDebugRows.isEmpty {
                    Text("約束がありません")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)
                } else {
                    ForEach(routineDebugRows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.subheadline)
                            Text(row.detail)
                                .font(.caption2)
                                .foregroundStyle(AppColor.muted)
                        }
                    }
                }
            }
        }
        .navigationTitle("デバッグ")
        .task { reload() }
    }

    private func numberField(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            TextField("0", value: value, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 96)
        }
    }

    private func reload() {
        let dependencies = AppDependencies(context: modelContext)
        let routines = dependencies.routineRepository.fetchAll()
        actualContinuousAchievementDays = RoutineStreak.overallStreak(routines: routines)

        do {
            let profileValues = try dependencies.storyStateRepository.profileValues()
            let continuousOverride = profileValues[
                StoryStateRepository.debugContinuousAchievementDaysKey
            ].flatMap(Int.init)
            cumulativeAchievementDays = profileValues[
                StoryStateRepository.debugCumulativeAchievementDaysKey
            ].flatMap(Int.init) ?? 0
            continuousAchievementDays = continuousOverride ?? actualContinuousAchievementDays
            isContinuousOverrideEnabled = continuousOverride != nil
            trust = profileValues[StoryStateRepository.trustKey].flatMap(Int.init) ?? 0
            relationshipPhase = try dependencies.storyStateRepository.relationshipPhase()
            feedbackMessage = nil
        } catch {
            feedbackMessage = "読み込みに失敗しました: \(error.localizedDescription)"
            feedbackIsError = true
        }

        routineDebugRows = routines.map { routine in
            let progress = routine.todayProgress()
            let streak = RoutineStreak.currentStreak(routine: routine)
            let percentage = Int((progress.fraction * 100).rounded())
            return RoutineDebugRow(
                id: routine.id,
                title: routine.title,
                detail: "\(routine.period.currentUnitLabel) \(progress.done)/\(progress.target)回 (\(percentage)%) ・ \(streak)日連続"
            )
        }
    }

    private func saveProgressValues() {
        cumulativeAchievementDays = max(0, cumulativeAchievementDays)
        continuousAchievementDays = max(0, continuousAchievementDays)
        trust = max(0, trust)
        relationshipPhase = max(0, relationshipPhase)

        let dependencies = AppDependencies(context: modelContext)
        var values = [
            StoryStateRepository.debugCumulativeAchievementDaysKey:
                String(cumulativeAchievementDays),
            StoryStateRepository.trustKey: String(trust),
            StoryStateRepository.relationshipPhaseKey: String(relationshipPhase),
        ]
        var removingKeys = Set<String>()
        if isContinuousOverrideEnabled {
            values[StoryStateRepository.debugContinuousAchievementDaysKey] =
                String(continuousAchievementDays)
        } else {
            removingKeys.insert(StoryStateRepository.debugContinuousAchievementDaysKey)
        }

        do {
            try dependencies.storyStateRepository.updateProfileValues(
                values,
                removingKeys: removingKeys
            )
            _ = try dependencies.storyUnlockService?.refreshUnlocks()
            feedbackMessage = "保存しました"
            feedbackIsError = false
        } catch {
            feedbackMessage = "保存に失敗しました: \(error.localizedDescription)"
            feedbackIsError = true
        }
    }
}
#endif

#Preview {
    NavigationStack {
        SettingsView()
    }
}
