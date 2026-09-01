import Foundation
import SwiftData

/// ModelContext から Repository を組み立てるための簡易ファクトリ。
@MainActor
struct AppDependencies {
    let routineRepository: RoutineRepository
    let blockedBehaviorRepository: BlockedBehaviorRepository
    let notificationScheduler: RoutineNotificationScheduler

    init(context: ModelContext) {
        routineRepository = RoutineRepository(context: context)
        blockedBehaviorRepository = BlockedBehaviorRepository(context: context)
        notificationScheduler = RoutineNotificationScheduler()
    }
}
