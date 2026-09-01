import Foundation

/// 1つの Routine の「今日の達成量 / 今日の目標量」。
/// Home の進捗円(Step 4 の ProgressCircle)や「2 / 4ステップ」表示に使う。
/// 過去30日の達成率(`RoutineLogViewModel`)とは無関係。
struct RoutineTodayProgress {
    /// 0.0〜1.0。進捗円はこの値で描く。
    let fraction: Double
    /// 今日完了した対象ステップ数。
    let completedSteps: Int
    /// 今日の目標ステップ数(`isRequired == true` のステップ数。0ステップRoutineは0)。
    let totalSteps: Int
    /// 今日のセッションが `.completed` まで到達しているか。
    let isCompletedToday: Bool

    /// ステップ数の内訳を「2 / 4ステップ」のように出すべきか(多ステップRoutineのみ true)。
    var showsStepBreakdown: Bool { totalSteps > 1 }
}

/// RoutineStep ベースの「今日の進捗」を履歴から計算する。
///
/// 将来の数量進捗(8,000歩 / 15分 / 3回 など)はこの計算に別ソースを足す形で拡張する想定。
/// このStepでは RoutineStep ベースのみ。
enum RoutineProgressCalculator {
    static func todayProgress(
        routine: Routine,
        sessions: [RoutineSession],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> RoutineTodayProgress {
        let today = calendar.startOfDay(for: now)

        // 今日のセッション(開始 or 完了が今日のもの、最新)。
        // 今日どれか1つでも .completed していれば「今日は達成」とみなす。
        var todaySession: RoutineSession?
        var isCompletedToday = false
        for session in sessions where session.routineId == routine.id {
            let startedToday = calendar.isDate(session.startedAt, inSameDayAs: now)
            var completedToday = false
            if let completedAt = session.completedAt {
                completedToday = calendar.startOfDay(for: completedAt) == today
            }
            guard startedToday || completedToday else { continue }
            if session.status == .completed, completedToday {
                isCompletedToday = true
            }
            if todaySession == nil || session.startedAt > todaySession!.startedAt {
                todaySession = session
            }
        }

        // 目標ステップ。isRequired 優先、無ければ全ステップ、0なら 0ステップRoutine。
        let requiredSteps = routine.orderedSteps.filter { $0.isRequired }
        let targetSteps = requiredSteps.isEmpty ? routine.orderedSteps : requiredSteps
        let totalSteps = targetSteps.count

        // 0ステップRoutine: セッション完了で 1、それ以外 0。
        guard totalSteps > 0 else {
            let done = isCompletedToday
            return RoutineTodayProgress(
                fraction: done ? 1 : 0,
                completedSteps: 0,
                totalSteps: 0,
                isCompletedToday: done
            )
        }

        // セッションが完了扱いなら、スキップ・失敗があっても今日の目標は達成(1.0)。
        if isCompletedToday {
            return RoutineTodayProgress(
                fraction: 1,
                completedSteps: totalSteps,
                totalSteps: totalSteps,
                isCompletedToday: true
            )
        }

        // 進行中/中断: 今日のセッションで「完了」した対象ステップ数を数える。
        let targetStepIds = Set(targetSteps.map { $0.id })
        var completedStepIds = Set<UUID>()
        if let session = todaySession {
            for event in session.events where event.eventType == .completedStep {
                if let stepId = event.stepId, targetStepIds.contains(stepId) {
                    completedStepIds.insert(stepId)
                }
            }
        }
        let completed = min(completedStepIds.count, totalSteps)

        return RoutineTodayProgress(
            fraction: Double(completed) / Double(totalSteps),
            completedSteps: completed,
            totalSteps: totalSteps,
            isCompletedToday: false
        )
    }
}
