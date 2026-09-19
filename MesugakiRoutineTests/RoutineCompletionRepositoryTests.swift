import SwiftData
import XCTest
@testable import MesugakiRoutine

@MainActor
final class RoutineCompletionRepositoryTests: XCTestCase {
    private var container: ModelContainer?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    func testSingleTargetCanBeCompletedAndReturnedToIncomplete() throws {
        let container = try makeContainer()
        let repository = RoutineRepository(context: container.mainContext)
        let now = try date(2026, 9, 19, 12)
        let routine = try insertRoutine(
            Routine(title: "本を読む", createdAt: try date(2026, 9, 19, 4)),
            into: container.mainContext
        )

        try repository.setCompletion(
            routine,
            completed: true,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(routine.progressCount(now: now, calendar: calendar), 1)
        XCTAssertTrue(routine.isComplete(now: now, calendar: calendar))

        try repository.setCompletion(
            routine,
            completed: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(routine.progressCount(now: now, calendar: calendar), 0)
        XCTAssertFalse(routine.isComplete(now: now, calendar: calendar))
        XCTAssertTrue(routine.progressEvents.isEmpty)
    }

    func testCompletingPartialMultiTargetAddsOnlyMissingEventsAndUndoRestoresOriginalProgress() throws {
        let container = try makeContainer()
        let repository = RoutineRepository(context: container.mainContext)
        let partialEvent = try date(2026, 9, 19, 8)
        let now = try date(2026, 9, 19, 12)
        let routine = try insertRoutine(
            Routine(
                title: "水を飲む",
                createdAt: try date(2026, 9, 19, 4),
                targetCount: 3,
                progressEvents: [partialEvent]
            ),
            into: container.mainContext
        )

        try repository.setCompletion(
            routine,
            completed: true,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(routine.progressEvents.count, 3)
        XCTAssertEqual(routine.progressEvents.filter { $0 == now }.count, 2)
        XCTAssertEqual(routine.progressCount(now: now, calendar: calendar), 3)
        XCTAssertTrue(routine.isComplete(now: now, calendar: calendar))

        try repository.setCompletion(
            routine,
            completed: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(routine.progressEvents.count, 1)
        XCTAssertTrue(routine.progressEvents.contains(partialEvent))
        XCTAssertEqual(routine.progressEvents.filter { $0 == now }.count, 0)
        XCTAssertEqual(routine.progressCount(now: now, calendar: calendar), 1)
        XCTAssertFalse(routine.isComplete(now: now, calendar: calendar))
    }

    func testRepeatedProgressReportsFillMultiTargetOneSliceAtATimeAndUndoOneSlice() throws {
        let container = try makeContainer()
        let repository = RoutineRepository(context: container.mainContext)
        let createdAt = try date(2026, 9, 19, 4)
        let first = try date(2026, 9, 19, 8)
        let second = try date(2026, 9, 19, 9)
        let third = try date(2026, 9, 19, 10)
        let routine = try insertRoutine(
            Routine(
                title: "水を飲む",
                createdAt: createdAt,
                targetCount: 3
            ),
            into: container.mainContext
        )

        try repository.recordProgress(routine, now: first)
        XCTAssertEqual(routine.todayProgress(now: first, calendar: calendar).done, 1)
        XCTAssertEqual(routine.todayProgress(now: first, calendar: calendar).fraction, 1.0 / 3.0, accuracy: 0.000_001)
        XCTAssertFalse(routine.isComplete(now: first, calendar: calendar))

        try repository.recordProgress(routine, now: second)
        XCTAssertEqual(routine.todayProgress(now: second, calendar: calendar).done, 2)
        XCTAssertEqual(routine.todayProgress(now: second, calendar: calendar).fraction, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertFalse(routine.isComplete(now: second, calendar: calendar))

        try repository.recordProgress(routine, now: third)
        XCTAssertEqual(routine.todayProgress(now: third, calendar: calendar).done, 3)
        XCTAssertEqual(routine.todayProgress(now: third, calendar: calendar).fraction, 1, accuracy: 0.000_001)
        XCTAssertTrue(routine.isComplete(now: third, calendar: calendar))

        try repository.setCompletion(
            routine,
            completed: false,
            now: third,
            calendar: calendar
        )
        XCTAssertEqual(routine.todayProgress(now: third, calendar: calendar).done, 2)
        XCTAssertEqual(routine.todayProgress(now: third, calendar: calendar).fraction, 2.0 / 3.0, accuracy: 0.000_001)
        XCTAssertFalse(routine.isComplete(now: third, calendar: calendar))
    }

    func testUndoRemovesOnlyNewestCurrentPeriodEventsAndPreservesPriorPeriods() throws {
        let container = try makeContainer()
        let repository = RoutineRepository(context: container.mainContext)
        let priorPeriodEvent = try date(2026, 9, 18, 12)
        let firstCurrentEvent = try date(2026, 9, 19, 8)
        let secondCurrentEvent = try date(2026, 9, 19, 10)
        let thirdCurrentEvent = try date(2026, 9, 19, 11)
        let newestCurrentEvent = try date(2026, 9, 19, 12)
        let now = try date(2026, 9, 19, 13)
        let routine = try insertRoutine(
            Routine(
                title: "ストレッチ",
                createdAt: try date(2026, 9, 18, 4),
                targetCount: 3,
                progressEvents: [
                    priorPeriodEvent,
                    firstCurrentEvent,
                    secondCurrentEvent,
                    thirdCurrentEvent,
                    newestCurrentEvent,
                ]
            ),
            into: container.mainContext
        )

        try repository.setCompletion(
            routine,
            completed: false,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(
            routine.progressEvents,
            [priorPeriodEvent, firstCurrentEvent, secondCurrentEvent]
        )
        XCTAssertEqual(
            routine.progressCount(now: now, calendar: calendar),
            2
        )
        XCTAssertFalse(routine.isComplete(now: now, calendar: calendar))
    }

    func testCompletionAndUndoPersistForNewModelContexts() throws {
        let container = try makeContainer()
        let repository = RoutineRepository(context: container.mainContext)
        let now = try date(2026, 9, 19, 12)
        let routine = try insertRoutine(
            Routine(
                title: "運動する",
                createdAt: try date(2026, 9, 19, 4),
                targetCount: 2
            ),
            into: container.mainContext
        )
        let routineID = routine.id

        try repository.setCompletion(
            routine,
            completed: true,
            now: now,
            calendar: calendar
        )

        var verificationContext = ModelContext(container)
        var persistedRoutine = try fetchRoutine(id: routineID, from: verificationContext)
        XCTAssertEqual(persistedRoutine.progressCount(now: now, calendar: calendar), 2)
        XCTAssertTrue(persistedRoutine.isComplete(now: now, calendar: calendar))

        let resumedRepository = RoutineRepository(context: verificationContext)
        try resumedRepository.setCompletion(
            persistedRoutine,
            completed: false,
            now: now,
            calendar: calendar
        )

        verificationContext = ModelContext(container)
        persistedRoutine = try fetchRoutine(id: routineID, from: verificationContext)
        XCTAssertEqual(persistedRoutine.progressCount(now: now, calendar: calendar), 0)
        XCTAssertFalse(persistedRoutine.isComplete(now: now, calendar: calendar))
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Routine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        return container
    }

    private func insertRoutine(_ routine: Routine, into context: ModelContext) throws -> Routine {
        context.insert(routine)
        try context.save()
        return routine
    }

    private func fetchRoutine(id: UUID, from context: ModelContext) throws -> Routine {
        let descriptor = FetchDescriptor<Routine>(
            predicate: #Predicate { $0.id == id }
        )
        return try XCTUnwrap(try context.fetch(descriptor).first)
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
