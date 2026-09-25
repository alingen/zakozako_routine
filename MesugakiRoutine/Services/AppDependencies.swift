import Foundation
import SwiftData

/// ModelContext から Repository を組み立てるための簡易ファクトリ。
@MainActor
struct AppDependencies {
    let routineRepository: RoutineRepository
    let blockedBehaviorRepository: BlockedBehaviorRepository
    let userActionEventRepository: UserActionEventRepository
    let reactionContextProvider: ReactionContextProvider
    let screenTimeMonitoringService: ScreenTimeMonitoringService
    let notificationScheduler: RoutineNotificationScheduler
    let storyStateRepository: StoryStateRepository
    let storyContentRepository: StoryContentRepository?
    let storyUnlockService: StoryUnlockService?

    init(context: ModelContext) {
        routineRepository = RoutineRepository(context: context)
        blockedBehaviorRepository = BlockedBehaviorRepository(context: context)
        userActionEventRepository = UserActionEventRepository(context: context)
        reactionContextProvider = ReactionContextProvider(context: context)
        screenTimeMonitoringService = ScreenTimeMonitoringService()
        notificationScheduler = RoutineNotificationScheduler()
        storyStateRepository = StoryStateRepository(context: context)

        let content = try? StoryContentRepository()
        storyContentRepository = content
        if let content {
            storyUnlockService = StoryUnlockService(
                contentRepository: content,
                stateRepository: storyStateRepository,
                metricsProvider: StoryProgressMetricsProvider(
                    routineRepository: routineRepository,
                    storyStateRepository: storyStateRepository
                )
            )
        } else {
            storyUnlockService = nil
        }
    }
}
