import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class OnboardingDeferredReportIntegrationTests: XCTestCase {
    private var container: ModelContainer?

    func testDeferringFirstReportDoesNotRecordAchievement() throws {
        let suiteName = "OnboardingDeferredReportIntegrationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try makeContainer()
        let context = container.mainContext
        let routineRepository = RoutineRepository(context: context)
        let storyStateRepository = StoryStateRepository(context: context)
        let metricsProvider = StoryProgressMetricsProvider(
            routineRepository: routineRepository,
            storyStateRepository: storyStateRepository
        )
        let routine = try routineRepository.create(
            title: "本を1ページ読む",
            cueText: "寝る前",
            iconName: "book"
        )
        let now = Date()

        let onboarding = OnboardingStateStore(defaults: defaults)
        onboarding.beginInAppTutorial(createdRoutineID: routine.id)
        onboarding.completePrologue()
        onboarding.completePrologueMessage()
        onboarding.completeFirstReport(with: .deferred)

        XCTAssertEqual(onboarding.firstReportOutcome, .deferred)
        XCTAssertEqual(onboarding.phase, .conversationPrompt)
        XCTAssertTrue(routine.progressEvents.isEmpty)
        XCTAssertEqual(routine.progressCount(now: now), 0)
        XCTAssertFalse(routine.isComplete(now: now))
        XCTAssertEqual(RoutineStreak.currentStreak(routine: routine, now: now), 0)
        XCTAssertEqual(
            RoutineStreak.overallStreak(routines: [routine], now: now),
            0
        )

        let metrics = try metricsProvider.current(at: now, calendar: .current)
        XCTAssertEqual(metrics.continuousDays, 0)
        XCTAssertEqual(metrics.cumulativeAchievementDays, 0)

        let verificationContext = ModelContext(container)
        let routineID = routine.id
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == routineID }
        )
        let persistedRoutine = try XCTUnwrap(
            try verificationContext.fetch(descriptor).first
        )
        XCTAssertTrue(persistedRoutine.progressEvents.isEmpty)
        XCTAssertEqual(persistedRoutine.progressCount(now: now), 0)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Routine.self,
            StoryEventProgress.self,
            StoryPlaybackProgress.self,
            StoryProfileValue.self,
            StoryMemoryUnlock.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        return container
    }
}
