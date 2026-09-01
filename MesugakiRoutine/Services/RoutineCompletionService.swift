import Foundation

/// ルーティンを1タップ進めた結果。完了演出(RoutineCompletionPresentation)の出し分けに使う。
struct RoutineAdvanceResult {
    /// このタップでルーティンが完了したか。
    let didComplete: Bool
    /// 完了後時点での、そのルーティンの連続達成回数。
    let currentStreak: Int
    /// この完了で、今日やる予定のルーティンがすべて完了したか。
    let allRoutinesCompletedToday: Bool
}

/// ルーティンの「1タップで1ステップ進める / 完了する」操作を担当する。
/// RoutineSessionView は廃止したので、Home から直接ここを呼ぶ。
@MainActor
final class RoutineCompletionService {
    private let routineRepository: RoutineRepository
    private let sessionRepository: RoutineSessionRepository
    private let engine: RoutineEngine

    init(routineRepository: RoutineRepository, sessionRepository: RoutineSessionRepository) {
        self.routineRepository = routineRepository
        self.sessionRepository = sessionRepository
        self.engine = RoutineEngine(sessionRepository: sessionRepository)
    }

    /// ルーティンを1つ進める。
    /// - ステップがあるルーティン: 現在のステップを完了 → 次へ。最後のステップならセッション完了。
    /// - 0ステップのルーティン: 1タップでセッション完了。
    /// - すでに今日完了済みなら何もしない。
    @discardableResult
    func advance(routine: Routine, calendar: Calendar = .current, now: Date = .now) -> RoutineAdvanceResult {
        let sessions = sessionRepository.fetchAllSessions()
        let alreadyDone = RoutineProgressCalculator
            .todayProgress(routine: routine, sessions: sessions, calendar: calendar, now: now)
            .isCompletedToday

        if !alreadyDone {
            let steps = routine.orderedSteps
            let session = sessionRepository.fetchActiveSession(routineId: routine.id) ?? {
                let created = sessionRepository.createSession(routineId: routine.id, currentStepId: steps.first?.id)
                sessionRepository.appendEvent(to: created, stepId: steps.first?.id, eventType: .started)
                return created
            }()

            let progress = engine.progress(session: session, routine: routine)
            if progress.currentStep != nil {
                _ = engine.recordOutcome(.completed, for: progress)
            } else {
                sessionRepository.updateCurrentStep(session, stepId: nil)
                sessionRepository.updateStatus(session, status: .completed, completedAt: now)
                sessionRepository.appendEvent(to: session, stepId: nil, eventType: .completedRoutine)
            }
        }

        let refreshed = sessionRepository.fetchAllSessions()
        let didComplete = RoutineProgressCalculator
            .todayProgress(routine: routine, sessions: refreshed, calendar: calendar, now: now)
            .isCompletedToday
        let streak = RoutineStreakCalculator.currentStreak(routine: routine, sessions: refreshed, calendar: calendar, now: now)
        return RoutineAdvanceResult(
            didComplete: didComplete && !alreadyDone,
            currentStreak: streak,
            allRoutinesCompletedToday: didComplete && allTodayRoutinesCompleted(calendar: calendar, now: now)
        )
    }

    /// 今日やる予定のルーティン(isActive かつ今日の曜日が対象)が、すべて今日完了しているか。
    /// 予定が0件のときは false。
    func allTodayRoutinesCompleted(calendar: Calendar = .current, now: Date = .now) -> Bool {
        let todayWeekday = calendar.component(.weekday, from: now)
        let todayRoutines = routineRepository.fetchAll().filter { routine in
            guard routine.isActive else { return false }
            return routine.activeWeekdayValues.isEmpty || routine.activeWeekdayValues.contains(todayWeekday)
        }
        guard !todayRoutines.isEmpty else { return false }

        let today = calendar.startOfDay(for: now)
        let completedRoutineIds = Set(
            sessionRepository.fetchAllSessions()
                .filter { session in
                    guard session.status == .completed else { return false }
                    guard let completedAt = session.completedAt else { return false }
                    return calendar.startOfDay(for: completedAt) == today
                }
                .map(\.routineId)
        )
        return todayRoutines.allSatisfy { completedRoutineIds.contains($0.id) }
    }
}
