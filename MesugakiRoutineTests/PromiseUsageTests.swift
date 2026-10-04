import XCTest
@testable import MesugakiRoutine

final class PromiseUsageTests: XCTestCase {
    func testTwoAllowedUsesDrainOneThirdEachAndTheThirdFails() {
        let expectedFractions = [1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0]
        let expectedRemaining = [2, 1, 0, 0]

        for used in 0...3 {
            let usage = PromiseUsage(used: used, allowed: 2, periodLabel: "今日")

            XCTAssertEqual(usage.remaining, expectedRemaining[used])
            XCTAssertEqual(usage.fraction, expectedFractions[used], accuracy: 0.0001)
            XCTAssertEqual(usage.nextUseFails, used >= 2)
            XCTAssertEqual(usage.failed, used == 3)
        }
    }

    func testQuitCompletelyFailsOnTheFirstUse() {
        let untouched = PromiseUsage(used: 0, allowed: 0, periodLabel: "今日")
        XCTAssertEqual(untouched.fraction, 1, accuracy: 0.0001)
        XCTAssertTrue(untouched.nextUseFails)
        XCTAssertFalse(untouched.failed)

        XCTAssertTrue(PromiseUsage(used: 1, allowed: 0, periodLabel: "今日").failed)
    }

    func testRemainingFractionDoesNotBecomeNegativePastLimit() {
        let usage = PromiseUsage(used: 5, allowed: 2, periodLabel: "今日")

        XCTAssertEqual(usage.remaining, 0)
        XCTAssertEqual(usage.fraction, 0, accuracy: 0.0001)
        XCTAssertTrue(usage.failed)
    }
}
