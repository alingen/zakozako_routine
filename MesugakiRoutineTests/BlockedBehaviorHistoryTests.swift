import XCTest
@testable import MesugakiRoutine

final class BlockedBehaviorHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 12, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func label(_ day: Int, month: Int = 9) -> Date {
        date(day, 0, month: month)
    }

    func testDailyLimitMarksOnlyTheDayItWasBrokenAndLeavesTodayUndecided() {
        let behavior = BlockedBehavior(
            title: "夜食を食べない",
            limitPeriod: .day,
            limitCount: 1,
            usageEvents: [date(3)],
            createdAt: date(1, 10)
        )
        let history = BlockedBehaviorHistory(behavior: behavior, now: date(5), calendar: calendar)

        XCTAssertNil(history.outcome(onCalendarDay: label(31, month: 8)))
        XCTAssertEqual(history.outcome(onCalendarDay: label(1)), .kept)
        XCTAssertEqual(history.outcome(onCalendarDay: label(2)), .kept)
        XCTAssertEqual(history.outcome(onCalendarDay: label(3)), .lost)
        XCTAssertEqual(history.outcome(onCalendarDay: label(4)), .kept)
        XCTAssertNil(history.outcome(onCalendarDay: label(5)), "今日はまだ決まっていない")
        XCTAssertNil(history.outcome(onCalendarDay: label(6)), "未来は結果なし")

        XCTAssertEqual(history.recentCount(days: 30), BlockedBehaviorRecordCount(kept: 3, lost: 1))
        XCTAssertEqual(history.longestStreak, 2)
    }

    func testTodayIsLostAsSoonAsTheLimitIsReached() {
        let behavior = BlockedBehavior(
            title: "夜食を食べない",
            usageEvents: [date(5, 9)],
            createdAt: date(1, 10)
        )
        let history = BlockedBehaviorHistory(behavior: behavior, now: date(5, 12), calendar: calendar)

        XCTAssertEqual(history.outcome(onCalendarDay: label(5)), .lost)
    }

    func testCurrentStreakDropsToZeroOnceTodayIsLost() {
        let keeping = BlockedBehavior(
            title: "夜食を食べない",
            currentStreakDays: 3,
            createdAt: date(1, 10)
        )
        XCTAssertEqual(BlockedBehaviorHistory(behavior: keeping, now: date(5), calendar: calendar).currentStreak, 3)

        let lostToday = BlockedBehavior(
            title: "夜食を食べない",
            usageEvents: [date(5, 9)],
            currentStreakDays: 3,
            createdAt: date(1, 10)
        )
        XCTAssertEqual(BlockedBehaviorHistory(behavior: lostToday, now: date(5, 12), calendar: calendar).currentStreak, 0)
    }

    func testUsageBeforeFourAMCountsForThePreviousDay() {
        let behavior = BlockedBehavior(
            title: "夜食を食べない",
            usageEvents: [date(4, 2)],
            createdAt: date(1, 10)
        )
        let history = BlockedBehaviorHistory(behavior: behavior, now: date(6), calendar: calendar)

        XCTAssertEqual(history.outcome(onCalendarDay: label(3)), .lost)
        XCTAssertEqual(history.outcome(onCalendarDay: label(4)), .kept)
    }

    func testMonthlyLimitLosesEveryRemainingDayAfterTheLimitIsReached() {
        let behavior = BlockedBehavior(
            title: "課金しない",
            limitPeriod: .month,
            limitCount: 2,
            usageEvents: [date(3), date(10)],
            createdAt: date(1, 10)
        )
        let history = BlockedBehaviorHistory(behavior: behavior, now: date(15), calendar: calendar)

        XCTAssertEqual(history.outcome(onCalendarDay: label(9)), .kept)
        XCTAssertEqual(history.outcome(onCalendarDay: label(10)), .lost)
        XCTAssertEqual(history.outcome(onCalendarDay: label(14)), .lost)
        XCTAssertEqual(history.outcome(onCalendarDay: label(15)), .lost)
        XCTAssertEqual(history.count(inMonthContaining: label(1)), BlockedBehaviorRecordCount(kept: 9, lost: 6))
    }

    func testScreenTimeUsesOnlyRecordedDaysAndSkipsUnmonitoredDaysInStreaks() {
        let behavior = BlockedBehavior(
            title: "動画を見すぎない",
            trackingKind: .screenTime,
            screenTimeVerifiedDays: [date(2, 4), date(4, 4), date(5, 4)],
            screenTimeFailedDays: [date(6, 4)],
            createdAt: date(1, 10)
        )
        let history = BlockedBehaviorHistory(behavior: behavior, now: date(8), calendar: calendar)

        XCTAssertNil(history.outcome(onCalendarDay: label(1)))
        XCTAssertEqual(history.outcome(onCalendarDay: label(2)), .kept)
        XCTAssertNil(history.outcome(onCalendarDay: label(3)), "監視できなかった日は結果なし")
        XCTAssertEqual(history.outcome(onCalendarDay: label(6)), .lost)
        XCTAssertEqual(history.longestStreak, 3, "監視できなかった日は連続を途切れさせない")
    }

    func testMasteredBehaviorStopsCountingAfterTheLastEvaluatedDay() {
        let behavior = BlockedBehavior(
            title: "夜食を食べない",
            lastCheckInDate: date(3, 4),
            masteredAt: date(4, 9),
            createdAt: date(1, 10)
        )
        let history = BlockedBehaviorHistory(behavior: behavior, now: date(10), calendar: calendar)

        XCTAssertEqual(history.outcome(onCalendarDay: label(3)), .kept)
        XCTAssertNil(history.outcome(onCalendarDay: label(4)))
        XCTAssertEqual(history.recentCount(days: 30), BlockedBehaviorRecordCount(kept: 3, lost: 0))
    }
}
