import XCTest
import SwiftUI
@testable import MesugakiRoutine

final class RioCopyTests: XCTestCase {
    func testListMovesDownOnlyForAbovePeekInCaptureMode() {
        let above = RioIdlePeekRequest.Kind.above(unfinishedRoutineTitle: nil)
        XCTAssertEqual(RioPromotionalCapture.listTopInset(for: above, enabled: true), 100)
        XCTAssertEqual(RioPromotionalCapture.listTopInset(for: above, enabled: false), 0)
        XCTAssertEqual(RioPromotionalCapture.listTopInset(for: .right(routineID: UUID()), enabled: true), 0)
        XCTAssertEqual(RioPromotionalCapture.listTopInset(for: nil, enabled: true), 0)
    }

    @MainActor
    func testPromotionalIdleTextWrapsWithinBubble() {
        XCTAssertEqual(RioPromotionalCapture.idleText, "まさかここから負けるなんて\nないよね〜♡")
        for width: CGFloat in [160, 240, 280] {
            let host = UIHostingController(rootView: RioPeekBubble(text: RioPromotionalCapture.idleText)
                .environment(\.rioPromotionalCapture, true)
                .environment(\.dynamicTypeSize, .large))
            let size = host.sizeThatFits(in: CGSize(width: width, height: 1000))
            XCTAssertLessThanOrEqual(size.width, width + 1)
            XCTAssertGreaterThan(size.height, 40)
            XCTAssertLessThan(size.height, 240)
        }
    }

    func testPromotionalIdlePeekBypassesLimitsWithoutChangingNormalHistory() throws {
        let suite = "RioCaptureTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let now = Date()

        XCTAssertEqual(RioUnrequestedPeekSchedule.idleDelay(promotionalCapture: true), 0.5)
        XCTAssertEqual(RioUnrequestedPeekSchedule.idleDelay(promotionalCapture: false), 10)
        for _ in 0..<4 {
            RioUnrequestedPeekSchedule.markShown(promotionalCapture: true, now: now, defaults: defaults)
            RioUnrequestedPeekSchedule.record(.dismissed(quickly: true), promotionalCapture: true, now: now, defaults: defaults)
        }
        XCTAssertTrue(RioUnrequestedPeekSchedule.canShow(now: now, defaults: defaults))
        XCTAssertFalse(RioUnrequestedPeekSchedule.canShow(alreadyShownThisOpen: true, now: now, defaults: defaults))

        for _ in 0..<3 {
            RioUnrequestedPeekSchedule.markShown(now: now, defaults: defaults)
            RioUnrequestedPeekSchedule.record(.dismissed(quickly: true), now: now, defaults: defaults)
        }
        XCTAssertFalse(RioUnrequestedPeekSchedule.canShow(now: now, defaults: defaults))
        XCTAssertTrue(RioUnrequestedPeekSchedule.canShow(promotionalCapture: true, alreadyShownThisOpen: true, now: now, defaults: defaults))
        XCTAssertFalse(RioUnrequestedPeekSchedule.canShow(now: now, defaults: defaults))
    }

    @MainActor
    func testPromotionalBubbleFitsFinalWOnCompactIPhone() {
        // 添付スクリーンショットの360pt幅と、13 mini標準の375pt幅を確認する。
        for screenWidth: CGFloat in [360, 375] {
            let bubbleWidth = screenWidth - RioPeekLayout.screenMargin - 140 * 0.72
            let host = UIHostingController(rootView: RioPeekBubble(text: "あははっキモ〜w")
                .environment(\.rioPromotionalCapture, true)
                .environment(\.dynamicTypeSize, .large))
            let size = host.sizeThatFits(in: CGSize(width: bubbleWidth, height: 1000))
            let lineHeight = UIFont.systemFont(ofSize: 15 * RioPromotionalCapture.textScale, weight: .semibold).lineHeight
            XCTAssertLessThanOrEqual(size.width, bubbleWidth + 1)
            XCTAssertLessThanOrEqual(size.height, lineHeight + 40 + 2, "末尾のwが別の行に折り返されないこと")
        }
    }

    func testTemplateExpandsMarkersBeforeInsertingUserSuppliedTitle() {
        let line = RioLine(lineId: "test", groupId: "notification", text: "今日は{routine_title}[br]A[sp]B",
                           weight: 1, active: true)
        XCTAssertEqual(line.displayText(routineTitle: "読書[br]"), "今日は読書[br]\nA B")
    }

    func testUserNamePlaceholderIsReplacedAndNeverShownRaw() {
        let line = RioLine(lineId: "test", groupId: "onboarding_intro", text: "お、ざこの{user_name}おにいさん発見〜",
                           weight: 1, active: true)
        XCTAssertEqual(line.displayText(userName: " ゆうた "), "お、ざこのゆうたおにいさん発見〜")
        XCTAssertEqual(line.displayText(), "お、ざこのおにいさん発見〜")
        // 名前に含まれる [br] 等はコマンドとして解釈しない。
        XCTAssertEqual(line.displayText(userName: "a[br]"), "お、ざこのa[br]おにいさん発見〜")
    }

    func testBundledCopyAndMigratedReactionsAreLoadedFromCMS() throws {
        let content = try StoryContentRepository()
        XCTAssertEqual(content.rioLines.count, 59)
        XCTAssertFalse(RioCopy.text("onboarding_intro_001").isEmpty)
        XCTAssertFalse(RioCopy.text("notification_not_started_001", routineTitle: "読書").contains("{routine_title}"))
        XCTAssertTrue(RioCopy.text("notification_not_started_001", routineTitle: "読書").contains("読書"))
        for group in ["home_routine_completed", "home_all_completed", "home_timer_finished",
                      "blocked_struggling", "blocked_defeated"] {
            XCTAssertTrue(RioCopy.lines(group: group).isEmpty)
            XCTAssertEqual(content.reactionLines.filter { $0.id.hasPrefix(group + "_") }.count, 3)
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
