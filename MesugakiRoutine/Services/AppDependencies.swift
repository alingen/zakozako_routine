import Foundation
import SwiftData

/// ModelContext から Repository / Engine を組み立てるための簡易ファクトリ。
/// ViewModel はこれを通じて依存を取得することで、SwiftUI の View から直接 SwiftData を触らない。
@MainActor
struct AppDependencies {
    let routineRepository: RoutineRepository
    let blockedBehaviorRepository: BlockedBehaviorRepository
    let sessionRepository: RoutineSessionRepository
    let routineEngine: RoutineEngine
    let routineCompletionService: RoutineCompletionService
    let notificationScheduler: RoutineNotificationScheduler

    init(context: ModelContext) {
        routineRepository = RoutineRepository(context: context)
        blockedBehaviorRepository = BlockedBehaviorRepository(context: context)
        sessionRepository = RoutineSessionRepository(context: context)
        routineEngine = RoutineEngine(sessionRepository: sessionRepository)
        routineCompletionService = RoutineCompletionService(
            routineRepository: routineRepository,
            sessionRepository: sessionRepository
        )
        notificationScheduler = RoutineNotificationScheduler()
    }
}
