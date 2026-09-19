import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class StoryProgressMetricsProviderTests: XCTestCase {
    private var container: ModelContainer?

    func testCumulativeAchievementDaysCountsUniqueAppDaysAcrossRoutines() throws {
        let repositories = try makeRepositories()
        let firstDayMorning = try date(2026, 9, 1, 10)
        let secondDayMorning = try date(2026, 9, 2, 10)
        let sameFirstAppDayAfterMidnight = try date(2026, 9, 2, 2)
        let historyStart = try date(2026, 8, 31, 4)

        insert(
            Routine(
                title: "本を読む",
                createdAt: historyStart,
                updatedAt: secondDayMorning,
                progressEvents: [firstDayMorning, secondDayMorning]
            ),
            into: repositories.context
        )
        insert(
            Routine(
                title: "運動する",
                createdAt: historyStart,
                updatedAt: sameFirstAppDayAfterMidnight,
                progressEvents: [sameFirstAppDayAfterMidnight]
            ),
            into: repositories.context
        )
        try repositories.context.save()

        let metrics = try repositories.provider.current(
            at: try date(2026, 9, 3, 12),
            calendar: calendar
        )

        XCTAssertEqual(metrics.cumulativeAchievementDays, 2)
    }

    func testCumulativeAchievementDaysUsesFourAMAppDayBoundary() throws {
        let repositories = try makeRepositories()
        let beforeBoundary = try date(2026, 9, 2, 3, 30)
        let afterBoundary = try date(2026, 9, 2, 4, 30)
        let historyStart = try date(2026, 9, 1, 4)
        insert(
            Routine(
                title: "勉強する",
                createdAt: historyStart,
                updatedAt: afterBoundary,
                progressEvents: [beforeBoundary, afterBoundary]
            ),
            into: repositories.context
        )
        try repositories.context.save()

        let metrics = try repositories.provider.current(
            at: try date(2026, 9, 2, 12),
            calendar: calendar
        )

        XCTAssertEqual(metrics.cumulativeAchievementDays, 2)
    }

    func testCumulativeAchievementDaysDoesNotCountPartialProgress() throws {
        let repositories = try makeRepositories()
        let event = try date(2026, 9, 1, 10)
        insert(
            Routine(
                title: "水を飲む",
                createdAt: try date(2026, 9, 1, 4),
                updatedAt: event,
                targetCount: 2,
                progressEvents: [event]
            ),
            into: repositories.context
        )
        try repositories.context.save()

        let metrics = try repositories.provider.current(
            at: try date(2026, 9, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(metrics.cumulativeAchievementDays, 0)
    }

    func testDebugCumulativeAchievementDaysOverridesRoutineHistory() throws {
        let repositories = try makeRepositories()
        let completedAt = try date(2026, 9, 1, 10)
        insert(
            Routine(
                title: "片づける",
                createdAt: try date(2026, 9, 1, 4),
                updatedAt: completedAt,
                progressEvents: [completedAt]
            ),
            into: repositories.context
        )
        try repositories.context.save()
        try repositories.storyStateRepository.updateProfileValues(
            [StoryStateRepository.debugCumulativeAchievementDaysKey: "9"]
        )

        let metrics = try repositories.provider.current(
            at: try date(2026, 9, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(metrics.cumulativeAchievementDays, 9)
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return value
    }

    private func makeRepositories() throws -> (
        provider: StoryProgressMetricsProvider,
        storyStateRepository: StoryStateRepository,
        context: ModelContext
    ) {
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
        let context = container.mainContext
        let routineRepository = RoutineRepository(context: context)
        let storyStateRepository = StoryStateRepository(context: context)
        return (
            StoryProgressMetricsProvider(
                routineRepository: routineRepository,
                storyStateRepository: storyStateRepository
            ),
            storyStateRepository,
            context
        )
    }

    private func insert(_ routine: Routine, into context: ModelContext) {
        context.insert(routine)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int = 0
    ) throws -> Date {
        try XCTUnwrap(
            calendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute
                )
            )
        )
    }
}
