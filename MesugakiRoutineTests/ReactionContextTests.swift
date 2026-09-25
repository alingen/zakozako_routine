import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class ReactionContextTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    func testTodayCountsMatchHomeAndCompletionTimeUsesExistingProgress() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let now = try date(2026, 9, 26, 12)
        let first = Routine(
            title: "勉強",
            createdAt: try date(2026, 9, 24, 4),
            progressEvents: [
                try date(2026, 9, 24, 9),
                try date(2026, 9, 25, 9),
                try date(2026, 9, 26, 8),
            ]
        )
        let second = Routine(
            title: "運動",
            createdAt: try date(2026, 9, 26, 4),
            targetCount: 2,
            progressEvents: [
                try date(2026, 9, 26, 8, 30),
                try date(2026, 9, 26, 10),
            ]
        )
        let inactive = Routine(title: "休止中", isActive: false, createdAt: try date(2026, 9, 26, 4))
        context.insert(first)
        context.insert(second)
        context.insert(inactive)
        try context.save()

        let actual = try ReactionContextProvider(context: context).current(now: now, calendar: calendar)
        let homeRoutines = HomeViewModel.computeTodayRoutines([first, second, inactive], calendar: calendar, now: now)
        XCTAssertEqual(actual.todayRoutineIDs, homeRoutines.map(\.id))
        XCTAssertEqual(actual.todayCompletedCount, 2)
        XCTAssertEqual(actual.remainingRoutineCount, 0)
        XCTAssertTrue(actual.isAllCompleted)
        XCTAssertEqual(actual.currentStreak, 3)
        XCTAssertEqual(actual.bestStreak, 3)
        XCTAssertEqual(actual.totalCompletionDays, 3)
        XCTAssertEqual(actual.allCompletedAt, try date(2026, 9, 26, 10))
        XCTAssertEqual(actual.routinePeriodFacts.first {
            $0.routineID == second.id && $0.completedAt != nil
        }?.completedAt, try date(2026, 9, 26, 10))
    }

    func testBestStreakSurvivesGapWhileCurrentStreakExpires() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let routine = Routine(
            title: "読書",
            createdAt: try date(2026, 9, 20, 4),
            progressEvents: [
                try date(2026, 9, 20, 8),
                try date(2026, 9, 21, 8),
                try date(2026, 9, 22, 8),
                try date(2026, 9, 24, 8),
            ]
        )
        context.insert(routine)
        try context.save()
        let provider = ReactionContextProvider(context: context)

        let day25 = try provider.current(now: date(2026, 9, 25, 12), calendar: calendar)
        XCTAssertEqual(day25.currentStreak, 1)
        XCTAssertEqual(day25.bestStreak, 3)
        XCTAssertEqual(day25.totalCompletionDays, 4)
        XCTAssertEqual(day25.daysSinceLastCompletion, 1)

        let day26 = try provider.current(now: date(2026, 9, 26, 12), calendar: calendar)
        XCTAssertEqual(day26.currentStreak, 0)
        XCTAssertEqual(day26.bestStreak, 3)
        XCTAssertEqual(day26.daysSinceLastCompletion, 2)
    }

    func testUrgeFailureAndVisitsCountAcrossFourAMBoundary() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let behavior = BlockedBehavior(
            title: "夜更かししない",
            limitCount: 2,
            createdAt: try date(2026, 9, 26, 4)
        )
        context.insert(behavior)
        try context.save()
        let blocked = BlockedBehaviorRepository(context: context)
        let events = UserActionEventRepository(context: context)

        try blocked.recordUrge(behavior, now: date(2026, 9, 27, 3, 59))
        try blocked.recordUrge(behavior, now: date(2026, 9, 27, 4))
        try blocked.recordUrge(behavior, now: date(2026, 9, 27, 4, 1))
        XCTAssertEqual(try blocked.recordFailure(behavior, now: date(2026, 9, 27, 4, 2), calendar: calendar), .recorded)
        XCTAssertEqual(try blocked.recordFailure(behavior, now: date(2026, 9, 27, 4, 3), calendar: calendar), .recorded)
        XCTAssertEqual(try blocked.recordFailure(behavior, now: date(2026, 9, 27, 4, 4), calendar: calendar), .alreadyRecorded)
        try events.record(.interactionScreenOpened, occurredAt: date(2026, 9, 27, 4, 5))
        try events.record(.interactionScreenOpened, occurredAt: date(2026, 9, 27, 4, 6))
        try events.record(.characterTapped, occurredAt: date(2026, 9, 27, 4, 7))

        let actual = try ReactionContextProvider(context: context).current(
            now: date(2026, 9, 27, 4, 15),
            calendar: calendar
        )
        XCTAssertEqual(actual.todayProhibitionUrgeCount, 2)
        XCTAssertEqual(actual.todayProhibitionFailCount, 2)
        XCTAssertEqual(actual.todayProhibitionOutcome, .lost)
        XCTAssertEqual(actual.todayInteractionOpenCount, 2)
        XCTAssertEqual(actual.todayCharacterTapCount, 1)
        XCTAssertEqual(behavior.usageEvents.count, 2)
        XCTAssertEqual(try events.fetchAll().filter { $0.targetID == behavior.id }.count, 5)
    }

    func testActionHistoryPersistsAcrossModelContainerReopen() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReactionContextTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("actions.store")
        let firstOpen = try date(2026, 9, 23, 12)
        let secondOpen = try date(2026, 9, 26, 12)

        do {
            let container = try makeContainer(url: storeURL)
            let context = container.mainContext
            let routine = Routine(
                title: "勉強",
                createdAt: try date(2026, 9, 25, 4),
                progressEvents: [
                    try date(2026, 9, 25, 9),
                    try date(2026, 9, 26, 9),
                ]
            )
            let behavior = BlockedBehavior(title: "夜更かししない", createdAt: try date(2026, 9, 26, 4))
            context.insert(routine)
            context.insert(behavior)
            try context.save()
            let repository = UserActionEventRepository(context: context)
            try repository.record(.appOpened, occurredAt: firstOpen)
            try repository.record(.appOpened, occurredAt: secondOpen)
            try repository.record(.interactionScreenOpened, occurredAt: secondOpen)
            try repository.record(.interactionScreenOpened, occurredAt: secondOpen.addingTimeInterval(30))
            try BlockedBehaviorRepository(context: context).recordUrge(
                behavior,
                now: secondOpen.addingTimeInterval(60)
            )
        }

        let reopened = try makeContainer(url: storeURL)
        let actual = try ReactionContextProvider(context: reopened.mainContext).current(
            now: try date(2026, 9, 26, 13),
            calendar: calendar
        )
        XCTAssertEqual(actual.lastAppOpenAt, secondOpen)
        XCTAssertEqual(actual.previousAppOpenAt, firstOpen)
        XCTAssertEqual(actual.daysSincePreviousAppOpen, 3)
        XCTAssertEqual(actual.todayInteractionOpenCount, 2)
        XCTAssertEqual(actual.todayProhibitionUrgeCount, 1)
        XCTAssertEqual(actual.currentStreak, 2)
        XCTAssertEqual(actual.totalCompletionDays, 2)
    }

    private func makeContainer(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Routine.self, BlockedBehavior.self, UserActionEvent.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
        try XCTUnwrap(calendar.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute
        )))
    }
}
