import XCTest
@testable import MesugakiRoutine

final class PromiseUsageTests: XCTestCase {
    func testRemainingFractionDrainsOneThirdForEachFailure() {
        let expectedFractions = [1.0, 2.0 / 3.0, 1.0 / 3.0, 0.0]

        for used in 0...3 {
            let usage = PromiseUsage(used: used, limit: 3, periodLabel: "今日")

            XCTAssertEqual(usage.remaining, 3 - used)
            XCTAssertEqual(usage.fraction, expectedFractions[used], accuracy: 0.0001)
            XCTAssertEqual(usage.failed, used == 3)
        }
    }

    func testRemainingFractionDoesNotBecomeNegativePastLimit() {
        let usage = PromiseUsage(used: 4, limit: 3, periodLabel: "今日")

        XCTAssertEqual(usage.remaining, 0)
        XCTAssertEqual(usage.fraction, 0, accuracy: 0.0001)
        XCTAssertTrue(usage.failed)
    }
}
