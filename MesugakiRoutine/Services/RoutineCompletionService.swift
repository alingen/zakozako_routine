import Foundation

/// ルーティン完了の副作用処理の結果。完了体験(Presentation)へ渡す表示用データの一部になる。
struct RoutineCompletionResult {
    /// この完了で信頼度が +1 されたか。同日2回目以降の完了なら false。
    let trustAwarded: Bool
    /// この完了で、今日やる予定のルーティンがすべて完了したか。
    /// キャラの声かけ(朝/夜ではなく「全部終わった」)や、将来の今日の会話の発火条件(Step 6)に使う。
    let allRoutinesCompletedToday: Bool
}

/// Routine が「完了した」という事実を起点に走る共通の完了後処理。
///
/// 完了副作用(Trust 加算・イベント条件の再評価)を1か所に集約する。多ステップの
/// `RoutineSessionView` から完了しても、Home からクイック完了しても、必ずここを通す。
///
/// - Trust 加算は `ConversationCoordinator` からここへ移動済み(二重加算しないよう
///   あちら側の加算処理は削除した)。
/// - 同じ Routine を同じ日に何度完了しても Trust は1回だけ増える(同日重複防止)。
@MainActor
final class RoutineCompletionService {
    private let routineRepository: RoutineRepository
    private let sessionRepository: RoutineSessionRepository
    private let trustRepository: TrustRepository
    private let freeTalkTopicProgressRepository: FreeTalkTopicProgressRepository
    private let eventUnlockService: EventUnlockService

    init(
        routineRepository: RoutineRepository,
        sessionRepository: RoutineSessionRepository,
        trustRepository: TrustRepository,
        freeTalkTopicProgressRepository: FreeTalkTopicProgressRepository,
        eventUnlockService: EventUnlockService
    ) {
        self.routineRepository = routineRepository
        self.sessionRepository = sessionRepository
        self.trustRepository = trustRepository
        self.freeTalkTopicProgressRepository = freeTalkTopicProgressRepository
        self.eventUnlockService = eventUnlockService
    }

    /// 完了後処理を適用する。**呼び出しは「対象セッションが `.completed` になった後」であること。**
    ///
    /// - Parameter routineId: 完了した Routine の id。
    /// - Returns: 完了体験(Presentation)へ渡すための結果。
    @discardableResult
    func applyCompletionSideEffects(
        routineId: UUID,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> RoutineCompletionResult {
        let today = calendar.startOfDay(for: now)
        let completedTodayCount = sessionRepository.fetchAllSessions().filter { session in
            guard session.routineId == routineId, session.status == .completed else { return false }
            guard let completedAt = session.completedAt else { return false }
            return calendar.startOfDay(for: completedAt) == today
        }.count

        // イベント条件の再評価は冪等なので毎回やってよい。
        eventUnlockService.refreshUnlocks()

        let allDone = allTodayRoutinesCompleted(calendar: calendar, now: now)

        // Trust 加算は「その日はじめての完了」だけ。
        // このメソッドは完了直後に呼ばれる前提なので、今日の completed が1件 = 初回。
        guard completedTodayCount <= 1 else {
            return RoutineCompletionResult(trustAwarded: false, allRoutinesCompletedToday: allDone)
        }
        trustRepository.increment(by: 1)
        trustRepository.tryAdvanceStage(topicProgressRepository: freeTalkTopicProgressRepository)
        // Trust が増えたので、信頼度条件のイベントをもう一度評価する。
        eventUnlockService.refreshUnlocks()
        return RoutineCompletionResult(trustAwarded: true, allRoutinesCompletedToday: allDone)
    }

    /// 今日やる予定のルーティン(isActive かつ今日の曜日が対象)が、すべて今日完了しているか。
    /// 予定が0件のときは false(「全部終わった」と言える状態ではない)。
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

    /// Home からのクイック完了(0〜1ステップの習慣向け)。
    /// セッションを作成 → `.completed` → `.completedRoutine` イベント → 共通完了処理。
    @discardableResult
    func completeQuickly(routine: Routine) -> RoutineCompletionResult {
        let session: RoutineSession
        if let active = sessionRepository.fetchActiveSession(routineId: routine.id) {
            session = active
        } else {
            session = sessionRepository.createSession(routineId: routine.id, currentStepId: nil)
            sessionRepository.appendEvent(to: session, stepId: nil, eventType: .started)
        }
        sessionRepository.updateCurrentStep(session, stepId: nil)
        sessionRepository.updateStatus(session, status: .completed, completedAt: .now)
        sessionRepository.appendEvent(to: session, stepId: nil, eventType: .completedRoutine)

        return applyCompletionSideEffects(routineId: routine.id)
    }
}
