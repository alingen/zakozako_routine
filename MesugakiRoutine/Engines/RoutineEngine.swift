import Foundation

/// ステップ完了/スキップ/失敗の結果として記録されるアウトカム。
enum StepOutcome {
    case completed
    case skipped
    case failed
}

/// 実行中セッションの現在地を表すスナップショット。View / ViewModel はこれだけを見て画面を組み立てる。
struct RoutineProgress {
    let session: RoutineSession
    let routine: Routine
    let currentStep: RoutineStep?
    let completedSteps: [RoutineStep]
    let remainingSteps: [RoutineStep]

    var isFinished: Bool {
        session.status != .active
    }

    var totalStepCount: Int {
        routine.orderedSteps.count
    }
}

/// ルーティンの実行フローを司るエンジン。
/// 「今どのステップにいるか」「次に何をすべきか」の判定と、完了/スキップ/失敗の記録を一手に引き受ける。
@MainActor
final class RoutineEngine {
    private let sessionRepository: RoutineSessionRepository

    init(sessionRepository: RoutineSessionRepository) {
        self.sessionRepository = sessionRepository
    }

    /// ルーティンを開始する。既に進行中のセッションがあれば再開する。
    @discardableResult
    func startSession(for routine: Routine) -> RoutineProgress {
        let steps = routine.orderedSteps
        let session: RoutineSession
        if let active = sessionRepository.fetchActiveSession(routineId: routine.id) {
            session = active
        } else {
            session = sessionRepository.createSession(routineId: routine.id, currentStepId: steps.first?.id)
            sessionRepository.appendEvent(to: session, stepId: steps.first?.id, eventType: .started)
        }
        return progress(session: session, routine: routine)
    }

    func progress(session: RoutineSession, routine: Routine) -> RoutineProgress {
        let steps = routine.orderedSteps
        guard session.status == .active, let currentId = session.currentStepId,
              let currentIndex = steps.firstIndex(where: { $0.id == currentId }) else {
            return RoutineProgress(session: session, routine: routine, currentStep: nil, completedSteps: steps, remainingSteps: [])
        }
        return RoutineProgress(
            session: session,
            routine: routine,
            currentStep: steps[currentIndex],
            completedSteps: Array(steps.prefix(currentIndex)),
            remainingSteps: Array(steps.suffix(from: currentIndex))
        )
    }

    /// 現在のステップの結果を記録し、次のステップへ進める。全ステップ終了なら自動でセッションを完了扱いにする。
    @discardableResult
    func recordOutcome(_ outcome: StepOutcome, for progress: RoutineProgress) -> RoutineProgress {
        guard let step = progress.currentStep else { return progress }
        let session = progress.session
        let routine = progress.routine

        let eventType: RoutineEventType
        switch outcome {
        case .completed: eventType = .completedStep
        case .skipped: eventType = .skippedStep
        case .failed: eventType = .failedStep
        }
        sessionRepository.appendEvent(to: session, stepId: step.id, eventType: eventType)

        let steps = routine.orderedSteps
        guard let currentIndex = steps.firstIndex(where: { $0.id == step.id }) else {
            return self.progress(session: session, routine: routine)
        }

        if let next = steps[safe: currentIndex + 1] {
            sessionRepository.updateCurrentStep(session, stepId: next.id)
        } else {
            sessionRepository.updateCurrentStep(session, stepId: nil)
            sessionRepository.updateStatus(session, status: .completed, completedAt: .now)
            sessionRepository.appendEvent(to: session, stepId: nil, eventType: .completedRoutine)
        }
        return self.progress(session: session, routine: routine)
    }

    /// ルーティンを途中終了する。
    func abandon(_ progress: RoutineProgress) {
        sessionRepository.updateStatus(progress.session, status: .abandoned, completedAt: .now)
        sessionRepository.appendEvent(to: progress.session, stepId: progress.session.currentStepId, eventType: .abandoned)
    }
}
