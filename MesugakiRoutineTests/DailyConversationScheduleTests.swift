import XCTest
@testable import MesugakiRoutine

final class DailyConversationScheduleTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 60 * 60)!
        return calendar
    }

    func testConversationAdvancesAtAppDayBoundary() throws {
        let anchor = try date(2026, 9, 1, 4, 0)

        XCTAssertEqual(
            DailyConversationSchedule.scenarioIndex(
                on: try date(2026, 9, 2, 3, 59),
                anchorDate: anchor,
                scenarioCount: 14,
                calendar: calendar
            ),
            0
        )
        XCTAssertEqual(
            DailyConversationSchedule.scenarioIndex(
                on: try date(2026, 9, 2, 4, 0),
                anchorDate: anchor,
                scenarioCount: 14,
                calendar: calendar
            ),
            1
        )
    }

    func testConversationWrapsAfterAvailableScenarios() throws {
        let anchor = try date(2026, 9, 1, 4, 0)
        XCTAssertEqual(
            DailyConversationSchedule.scenarioIndex(
                on: try date(2026, 9, 15, 4, 0),
                anchorDate: anchor,
                scenarioCount: 14,
                calendar: calendar
            ),
            0
        )
    }

    func testEmptyCatalogHasNoSelection() throws {
        XCTAssertNil(
            DailyConversationSchedule.scenarioIndex(
                anchorDate: try date(2026, 9, 1, 4, 0),
                scenarioCount: 0,
                calendar: calendar
            )
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int
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
