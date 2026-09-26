import XCTest
@testable import MesugakiRoutine

final class RioCopyTests: XCTestCase {
    func testTemplateExpandsMarkersBeforeInsertingUserSuppliedTitle() {
        let line = RioLine(lineId: "test", groupId: "notification", text: "今日は{routine_title}[br]A[sp]B",
                           weight: 1, active: true)
        XCTAssertEqual(line.displayText(routineTitle: "読書[br]"), "今日は読書[br]\nA B")
    }

    func testBundledCopyAndFallbacksAreLoadedFromCMS() throws {
        let content = try StoryContentRepository()
        XCTAssertEqual(content.rioLines.count, 74)
        XCTAssertFalse(RioCopy.text("onboarding_intro_001").isEmpty)
        XCTAssertFalse(RioCopy.text("notification_not_started_001", routineTitle: "読書").contains("{routine_title}"))
        XCTAssertTrue(RioCopy.text("notification_not_started_001", routineTitle: "読書").contains("読書"))
        for group in ["home_routine_completed", "home_all_completed", "home_timer_finished",
                      "blocked_struggling", "blocked_defeated"] {
            XCTAssertEqual(RioCopy.lines(group: group).count, 3)
            XCTAssertTrue(RioCopy.lines(group: group).contains(try XCTUnwrap(RioCopy.random(group: group))))
        }
        XCTAssertEqual(RioCopy.text("missing"), "")
        XCTAssertNil(RioCopy.random(group: "missing"))
    }

    func testRepositoryExcludesDisabledAndZeroWeightCopy() throws {
        let content = try StoryContentRepository(content: StoryContentBundle(scenarios: [], choiceGroups: [], rioLines: [
            RioLine(lineId: "off", groupId: "test", text: "off", weight: 1, active: false),
            RioLine(lineId: "zero", groupId: "test", text: "zero", weight: 0, active: true),
            RioLine(lineId: "on", groupId: "test", text: "on", weight: 1, active: true)
        ], events: []))
        XCTAssertEqual(content.rioLines.map(\.id), ["on"])
    }
}
