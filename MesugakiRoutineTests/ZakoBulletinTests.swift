import XCTest
@testable import MesugakiRoutine

final class ZakoBulletinTests: XCTestCase {
    @MainActor
    func testBulletinUsesAchievementAndFailureKinds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 12))
        )
        let achievementDate = now.addingTimeInterval(-7_200)
        let failureDate = now.addingTimeInterval(-3_600)

        let routine = Routine(
            title: "本を読む",
            createdAt: now.addingTimeInterval(-10_800),
            targetCount: 1,
            progressEvents: [achievementDate]
        )
        let behavior = BlockedBehavior(
            title: "スマホを見ない",
            limitCount: 1,
            usageEvents: [failureDate],
            createdAt: now.addingTimeInterval(-10_800)
        )

        let items = HomeViewModel.buildBulletin(
            routines: [routine],
            behavior: behavior,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].kind, .failure)
        XCTAssertEqual(items[1].kind, .achievement)
    }
}
