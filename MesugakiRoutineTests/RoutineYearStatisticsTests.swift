import SwiftData
import XCTest
@testable import MesugakiRoutine

final class RoutineYearStatisticsTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    func testDailyStatisticsCountApplicableDaysAndLongestRun() throws {
        let routine = Routine(
            title: "本を読む",
            createdAt: try date(2026, 1, 1, 4),
            progressEvents: [
                try date(2026, 1, 1, 8),
                try date(2026, 1, 3, 8),
            ]
        )

        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2026,
            now: try date(2026, 1, 3, 20),
            calendar: calendar
        )

        XCTAssertEqual(statistics.applicableCount, 3)
        XCTAssertEqual(statistics.completedCount, 2)
        XCTAssertEqual(statistics.completionRate, 2.0 / 3.0, accuracy: 0.0001)
        XCTAssertEqual(statistics.longestStreak, 1)
        XCTAssertEqual(statistics.monthly[0].applicableCount, 3)
        XCTAssertEqual(statistics.monthly[0].completedCount, 2)
    }

    func testTargetCountUsesNthEventAsTheSingleCompletionTime() throws {
        let routine = Routine(
            title: "水を飲む",
            createdAt: try date(2026, 1, 5, 4),
            period: .day,
            targetCount: 2,
            progressEvents: [
                try date(2026, 1, 5, 8),
                try date(2026, 1, 5, 18),
            ]
        )

        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2026,
            now: try date(2026, 1, 5, 20),
            calendar: calendar
        )

        XCTAssertEqual(statistics.completedCount, 1)
        XCTAssertEqual(statistics.hours.first { $0.hour == 8 }?.completedCount, 0)
        XCTAssertEqual(statistics.hours.first { $0.hour == 18 }?.completedCount, 1)
        XCTAssertEqual(statistics.weekdays.reduce(0) { $0 + $1.completedCount }, 1)
    }

    func testAppDayBoundaryAssigns0359ToPreviousYearAnd0400ToNewYear() throws {
        let routine = Routine(
            title: "日記を書く",
            createdAt: try date(2025, 12, 31, 4),
            progressEvents: [
                try date(2026, 1, 1, 3, 59),
                try date(2026, 1, 1, 4),
            ]
        )
        let now = try date(2026, 1, 1, 5)

        let previousYear = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2025,
            now: now,
            calendar: calendar
        )
        let newYear = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2026,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(previousYear.completedCount, 1)
        XCTAssertEqual(previousYear.hours.first { $0.hour == 3 }?.completedCount, 1)
        XCTAssertEqual(previousYear.weekdays.first { $0.weekday == 4 }?.completedCount, 1)
        XCTAssertEqual(newYear.completedCount, 1)
        XCTAssertEqual(newYear.hours.first { $0.hour == 4 }?.completedCount, 1)
        XCTAssertEqual(newYear.weekdays.first { $0.weekday == 5 }?.completedCount, 1)
    }

    func testLongestStreakSkipsUnscheduledDays() throws {
        let mondayThroughFriday = [2, 3, 4, 5, 6]
        let routine = Routine(
            title: "勉強する",
            createdAt: try date(2026, 1, 5, 4),
            activeWeekdayValues: mondayThroughFriday,
            progressEvents: [
                try date(2026, 1, 5, 12),
                try date(2026, 1, 6, 12),
                try date(2026, 1, 8, 12),
                try date(2026, 1, 9, 12),
            ]
        )

        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2026,
            now: try date(2026, 1, 11, 20),
            calendar: calendar
        )

        XCTAssertEqual(statistics.applicableCount, 5)
        XCTAssertEqual(statistics.completedCount, 4)
        XCTAssertEqual(statistics.longestStreak, 2)
    }

    func testWeeklyRoutineCreatesOneOpportunityPerWeek() throws {
        let routine = Routine(
            title: "運動する",
            createdAt: try date(2026, 1, 4, 4),
            period: .week,
            targetCount: 2,
            progressEvents: [
                try date(2026, 1, 5, 8),
                try date(2026, 1, 6, 18),
            ]
        )

        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2026,
            now: try date(2026, 1, 20, 20),
            calendar: calendar
        )

        XCTAssertEqual(statistics.applicableCount, 3)
        XCTAssertEqual(statistics.completedCount, 1)
        XCTAssertEqual(statistics.longestStreak, 1)
        XCTAssertEqual(statistics.hours.first { $0.hour == 18 }?.completedCount, 1)
    }

    func testMonthlyRoutineCreatesOneOpportunityPerMonth() throws {
        let routine = Routine(
            title: "片付ける",
            createdAt: try date(2026, 1, 10, 4),
            period: .month,
            targetCount: 1,
            progressEvents: [
                try date(2026, 1, 15, 12),
                try date(2026, 2, 15, 12),
            ]
        )

        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2026,
            now: try date(2026, 3, 20, 20),
            calendar: calendar
        )

        XCTAssertEqual(statistics.applicableCount, 3)
        XCTAssertEqual(statistics.completedCount, 2)
        XCTAssertEqual(statistics.longestStreak, 2)
        XCTAssertEqual(statistics.monthly[0].applicableCount, 1)
        XCTAssertEqual(statistics.monthly[1].completedCount, 1)
        XCTAssertEqual(statistics.monthly[2].completedCount, 0)
    }

    func testPastLeapYearIncludesAll366Days() throws {
        let routine = Routine(
            title: "毎日の約束",
            createdAt: try date(2024, 1, 1, 4)
        )

        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2024,
            now: try date(2026, 1, 1, 12),
            calendar: calendar
        )

        XCTAssertEqual(statistics.applicableCount, 366)
        XCTAssertEqual(statistics.completedCount, 0)
        XCTAssertEqual(statistics.completionRate, 0)
    }

    func testAvailableYearsUseAppDayBoundaryForHistoryStart() throws {
        let beforeBoundary = try date(2025, 1, 1, 3, 59)
        let afterBoundary = try date(2025, 1, 1, 4)
        let beforeBoundaryRoutine = Routine(
            title: "深夜の散歩",
            createdAt: beforeBoundary
        )
        let afterBoundaryRoutine = Routine(
            title: "朝の散歩",
            createdAt: afterBoundary
        )

        XCTAssertEqual(
            RoutineYearStatisticsCalculator.availableYears(
                for: beforeBoundaryRoutine,
                now: try date(2026, 9, 12, 12),
                calendar: calendar
            ),
            [2024, 2025, 2026]
        )
        XCTAssertEqual(
            RoutineYearStatisticsCalculator.availableYears(
                for: afterBoundaryRoutine,
                now: try date(2026, 9, 12, 12),
                calendar: calendar
            ),
            [2025, 2026]
        )
    }

    func testRecentSummaryUsesFourAMBoundary() throws {
        let routine = Routine(
            title: "夜更かし記録",
            createdAt: try date(2026, 8, 13, 4),
            progressEvents: [
                try date(2026, 8, 13, 8),
                try date(2026, 9, 12, 2),
            ]
        )

        let summary = RoutineYearStatisticsCalculator.recentSummary(
            for: routine,
            now: try date(2026, 9, 12, 2, 30),
            calendar: calendar
        )

        XCTAssertEqual(summary.applicableCount, 30)
        XCTAssertEqual(summary.completedCount, 2)
    }

    func testWeeklyCompletionHasOneCompletionDate() throws {
        let completion = try date(2026, 1, 6, 18)
        let routine = Routine(
            title: "週2回運動する",
            createdAt: try date(2026, 1, 4, 4),
            period: .week,
            targetCount: 2,
            progressEvents: [
                try date(2026, 1, 5, 8),
                completion,
            ]
        )
        let now = try date(2026, 1, 10, 20)

        XCTAssertEqual(
            RoutineYearStatisticsCalculator.completionDate(
                for: routine,
                inPeriodContaining: try date(2026, 1, 6, 4),
                now: now,
                calendar: calendar
            ),
            completion
        )
        XCTAssertEqual(
            RoutineYearStatisticsCalculator.completionDate(
                for: routine,
                inPeriodContaining: try date(2026, 1, 9, 4),
                now: now,
                calendar: calendar
            ),
            completion
        )
        XCTAssertTrue(
            RoutineYearStatisticsCalculator.wasCompleted(
                routine,
                on: try date(2026, 1, 6, 4),
                now: now,
                calendar: calendar
            )
        )
        XCTAssertFalse(
            RoutineYearStatisticsCalculator.wasCompleted(
                routine,
                on: try date(2026, 1, 7, 4),
                now: now,
                calendar: calendar
            )
        )

        XCTAssertEqual(
            RoutineStreak.overallStreak(
                routines: [routine],
                now: try date(2026, 1, 7, 12),
                calendar: calendar
            ),
            1
        )
    }

    func testRecentSummaryIncludesAWeeklyPeriodCrossingItsLeftEdge() throws {
        let routine = Routine(
            title: "週1回片付ける",
            createdAt: try date(2025, 12, 1, 4),
            period: .week,
            progressEvents: [try date(2026, 1, 1, 12)]
        )

        // 直近30日は2025/12/30〜2026/1/28。12/28開始の週もこの範囲と重なる。
        let summary = RoutineYearStatisticsCalculator.recentSummary(
            for: routine,
            now: try date(2026, 1, 28, 12),
            calendar: calendar
        )

        XCTAssertEqual(summary.applicableCount, 5)
        XCTAssertEqual(summary.completedCount, 1)
    }

    func testCrossYearWeekBelongsToItsCompletionYear() throws {
        let completion = try date(2026, 1, 2, 12)
        let routine = Routine(
            title: "週1回運動する",
            createdAt: try date(2025, 12, 28, 4),
            period: .week,
            progressEvents: [completion]
        )
        let now = try date(2026, 1, 5, 12)

        let previousYear = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2025,
            now: now,
            calendar: calendar
        )
        let completionYear = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: 2026,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(previousYear.applicableCount, 0)
        XCTAssertEqual(previousYear.completedCount, 0)
        XCTAssertEqual(completionYear.applicableCount, 2)
        XCTAssertEqual(completionYear.completedCount, 1)
        XCTAssertEqual(completionYear.monthly[0].completedCount, 1)
        XCTAssertTrue(
            RoutineYearStatisticsCalculator.wasCompleted(
                routine,
                on: try date(2026, 1, 2, 4),
                now: now,
                calendar: calendar
            )
        )
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

@MainActor
final class RoutineRepositoryHistoryTests: XCTestCase {
    private var container: ModelContainer?

    func testRecordingProgressKeepsEventsOlderThanThreeMonths() throws {
        let schema = Schema([Routine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        let repository = RoutineRepository(context: container.mainContext)
        let oldEvent = Date(timeIntervalSince1970: 1_735_689_600)
        let newEvent = Date(timeIntervalSince1970: 1_757_635_200)
        let routine = Routine(
            title: "記録を残す",
            createdAt: oldEvent,
            progressEvents: [oldEvent]
        )
        container.mainContext.insert(routine)
        try container.mainContext.save()

        try repository.recordProgress(routine, now: newEvent)

        XCTAssertEqual(routine.progressEvents, [oldEvent, newEvent])

        let verificationContext = ModelContext(container)
        let persistedRoutine = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<Routine>()).first { $0.id == routine.id }
        )
        XCTAssertEqual(persistedRoutine.progressEvents, [oldEvent, newEvent])
    }

    func testChangingCompletionRulesStartsANewStatisticsHistory() throws {
        let schema = Schema([Routine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        let repository = RoutineRepository(context: container.mainContext)
        let oldEvent = Date(timeIntervalSince1970: 1_757_635_200)
        let ruleChangedAt = oldEvent.addingTimeInterval(3_600)
        let routine = Routine(
            title: "水を飲む",
            createdAt: oldEvent,
            progressEvents: [oldEvent]
        )
        container.mainContext.insert(routine)

        try repository.update(
            routine,
            title: routine.title,
            isActive: true,
            iconName: routine.iconName,
            period: .day,
            targetCount: 2,
            scheduledStartMinute: nil,
            activeWeekdayValues: Weekday.allWeekdayValues,
            now: ruleChangedAt
        )

        XCTAssertEqual(routine.currentRuleStartedAt, ruleChangedAt)
        XCTAssertEqual(routine.progressCount(now: ruleChangedAt.addingTimeInterval(60)), 0)
        XCTAssertFalse(routine.isComplete(now: ruleChangedAt.addingTimeInterval(60)))
        XCTAssertNotNil(routine.progressStatisticsArchiveData)

        let year = Calendar.current.component(.year, from: ruleChangedAt)
        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: year,
            now: ruleChangedAt.addingTimeInterval(60)
        )
        XCTAssertEqual(statistics.applicableCount, 2)
        XCTAssertEqual(statistics.completedCount, 1)
        XCTAssertEqual(RoutineStreak.currentStreak(routine: routine, now: ruleChangedAt), 0)
        XCTAssertEqual(
            RoutineYearStatisticsCalculator.recentSummary(
                for: routine,
                now: ruleChangedAt.addingTimeInterval(60)
            ).unitLabel,
            "件"
        )

        try repository.recordProgress(routine, now: ruleChangedAt.addingTimeInterval(120))
        XCTAssertEqual(routine.progressCount(now: ruleChangedAt.addingTimeInterval(120)), 1)
        XCTAssertFalse(routine.isComplete(now: ruleChangedAt.addingTimeInterval(120)))

        try repository.recordProgress(routine, now: ruleChangedAt.addingTimeInterval(180))
        let completedUnderNewRule = ruleChangedAt.addingTimeInterval(180)
        XCTAssertEqual(routine.progressCount(now: completedUnderNewRule), 2)
        XCTAssertTrue(routine.isComplete(now: completedUnderNewRule))
        XCTAssertEqual(RoutineStreak.currentStreak(routine: routine, now: completedUnderNewRule), 1)

        let updatedStatistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: year,
            now: completedUnderNewRule
        )
        XCTAssertEqual(updatedStatistics.applicableCount, 2)
        XCTAssertEqual(updatedStatistics.completedCount, 2)
        XCTAssertEqual(
            RoutineYearStatisticsCalculator.completionDates(
                for: routine,
                now: completedUnderNewRule
            ).count,
            2
        )

        let verificationContext = ModelContext(container)
        let persistedRoutine = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<Routine>()).first { $0.id == routine.id }
        )
        XCTAssertEqual(persistedRoutine.currentRuleStartedAt, ruleChangedAt)
        XCTAssertEqual(persistedRoutine.progressStatisticsArchiveData, routine.progressStatisticsArchiveData)
        let archiveObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(
                with: XCTUnwrap(persistedRoutine.progressStatisticsArchiveData)
            ) as? [String: Any]
        )
        XCTAssertEqual(archiveObject["version"] as? Int, 1)
    }

    func testLoweringTargetResetsCurrentSegmentConsistently() throws {
        let schema = Schema([Routine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        let repository = RoutineRepository(context: container.mainContext)
        let firstEvent = Date(timeIntervalSince1970: 1_757_635_200)
        let ruleChangedAt = firstEvent.addingTimeInterval(3_600)
        let routine = Routine(
            title: "ストレッチ",
            createdAt: firstEvent,
            period: .day,
            targetCount: 2,
            progressEvents: [firstEvent]
        )
        container.mainContext.insert(routine)
        try container.mainContext.save()

        try repository.update(
            routine,
            title: routine.title,
            isActive: true,
            iconName: routine.iconName,
            period: .day,
            targetCount: 1,
            scheduledStartMinute: nil,
            activeWeekdayValues: Weekday.allWeekdayValues,
            now: ruleChangedAt
        )

        XCTAssertEqual(routine.progressCount(now: ruleChangedAt), 0)
        XCTAssertFalse(routine.isComplete(now: ruleChangedAt))
        let beforeNewEvent = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: Calendar.current.component(.year, from: ruleChangedAt),
            now: ruleChangedAt
        )
        XCTAssertEqual(beforeNewEvent.applicableCount, 1)
        XCTAssertEqual(beforeNewEvent.completedCount, 0)

        let newEvent = ruleChangedAt.addingTimeInterval(60)
        try repository.recordProgress(routine, now: newEvent)

        XCTAssertTrue(routine.isComplete(now: newEvent))
        let afterNewEvent = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: Calendar.current.component(.year, from: newEvent),
            now: newEvent
        )
        XCTAssertEqual(afterNewEvent.applicableCount, 1)
        XCTAssertEqual(afterNewEvent.completedCount, 1)
        XCTAssertEqual(RoutineStreak.currentStreak(routine: routine, now: newEvent), 1)
    }

    func testMultipleRuleChangesPersistWithoutDuplicateArchiveOutcomes() throws {
        let schema = Schema([Routine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        let repository = RoutineRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 1_757_635_200)
        let routine = Routine(
            title: "水を飲む",
            createdAt: start,
            progressEvents: [start]
        )
        container.mainContext.insert(routine)
        try container.mainContext.save()

        let firstChange = start.addingTimeInterval(60)
        try repository.update(
            routine,
            title: routine.title,
            isActive: true,
            iconName: nil,
            period: .day,
            targetCount: 2,
            scheduledStartMinute: nil,
            activeWeekdayValues: Weekday.allWeekdayValues,
            now: firstChange
        )
        try repository.recordProgress(routine, now: firstChange.addingTimeInterval(60))
        try repository.recordProgress(routine, now: firstChange.addingTimeInterval(120))

        let secondChange = firstChange.addingTimeInterval(180)
        try repository.update(
            routine,
            title: routine.title,
            isActive: true,
            iconName: nil,
            period: .day,
            targetCount: 3,
            scheduledStartMinute: nil,
            activeWeekdayValues: Weekday.allWeekdayValues,
            now: secondChange
        )
        try repository.recordProgress(routine, now: secondChange.addingTimeInterval(60))
        try repository.recordProgress(routine, now: secondChange.addingTimeInterval(120))
        let finalCompletion = secondChange.addingTimeInterval(180)
        try repository.recordProgress(routine, now: finalCompletion)

        let year = Calendar.current.component(.year, from: start)
        let statistics = RoutineYearStatisticsCalculator.calculate(
            routine: routine,
            year: year,
            now: finalCompletion
        )
        XCTAssertEqual(statistics.applicableCount, 3)
        XCTAssertEqual(statistics.completedCount, 3)

        let verificationContext = ModelContext(container)
        let persistedRoutine = try XCTUnwrap(
            try verificationContext.fetch(FetchDescriptor<Routine>()).first { $0.id == routine.id }
        )
        let persistedStatistics = RoutineYearStatisticsCalculator.calculate(
            routine: persistedRoutine,
            year: year,
            now: finalCompletion
        )
        XCTAssertEqual(persistedStatistics, statistics)
        XCTAssertEqual(
            RoutineYearStatisticsCalculator.completionDates(
                for: persistedRoutine,
                now: finalCompletion
            ).count,
            3
        )
    }

    func testCorruptArchiveStopsRuleChangeWithoutOverwritingHistory() throws {
        let schema = Schema([Routine.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        self.container = container
        let repository = RoutineRepository(context: container.mainContext)
        let start = Date(timeIntervalSince1970: 1_757_635_200)
        let corruptArchive = Data("not valid json".utf8)
        let routine = Routine(
            title: "履歴を守る",
            createdAt: start,
            progressEvents: [start]
        )
        routine.progressStatisticsArchiveData = corruptArchive
        container.mainContext.insert(routine)
        try container.mainContext.save()

        XCTAssertThrowsError(
            try repository.update(
                routine,
                title: routine.title,
                isActive: true,
                iconName: nil,
                period: .day,
                targetCount: 2,
                scheduledStartMinute: nil,
                activeWeekdayValues: Weekday.allWeekdayValues,
                now: start.addingTimeInterval(60)
            )
        ) { error in
            XCTAssertTrue(error is RoutineStatisticsArchiveError)
        }
        XCTAssertEqual(routine.targetCount, 1)
        XCTAssertEqual(routine.currentRuleStartedAt, start)
        XCTAssertEqual(routine.progressStatisticsArchiveData, corruptArchive)
    }

}
