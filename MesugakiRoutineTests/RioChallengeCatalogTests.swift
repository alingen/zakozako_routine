import XCTest
@testable import MesugakiRoutine

final class RioChallengeCatalogTests: XCTestCase {
    func testBundledCatalogContainsAllInitialChallenges() throws {
        let catalog = try RioChallengeCatalog.load()
        XCTAssertEqual(catalog.challenges.count, 39)
        XCTAssertEqual(Set(catalog.challenges.map(\.id)).count, 39)
        XCTAssertEqual(Set(catalog.challenges.map(\.text)).count, 39)
        XCTAssertTrue(catalog.challenges.allSatisfy {
            $0.enabled && !$0.id.isEmpty && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })
        let counts = Dictionary(grouping: catalog.challenges, by: \.category).mapValues(\.count)
        XCTAssertEqual(counts, [
            .standard: 5, .silly: 10, .exercise: 5, .music: 4,
            .memory: 5, .observation: 5, .smallTask: 5,
        ])
    }

    func testRepeatedRerollsNeverReturnPreviousChallenge() throws {
        let catalog = try RioChallengeCatalog.load()
        var random = SeededRandomGenerator(seed: 42)
        var previousID: String?
        var seenIDs: Set<String> = []
        for _ in 0..<5_000 {
            let next = try XCTUnwrap(catalog.next(excluding: previousID, using: &random))
            XCTAssertNotEqual(next.id, previousID)
            XCTAssertTrue(catalog.challenges.contains(next))
            seenIDs.insert(next.id)
            previousID = next.id
        }
        XCTAssertEqual(seenIDs.count, 39)
    }

    func testCategoryWeightsAreIndependentOfNumberOfChallenges() throws {
        let catalog = try RioChallengeCatalog.load()
        var random = SeededRandomGenerator(seed: 123)
        var counts: [RioChallenge.Category: Int] = [:]
        let draws = 20_000
        for _ in 0..<draws {
            let next = try XCTUnwrap(catalog.next(using: &random))
            counts[next.category, default: 0] += 1
        }
        for category in RioChallenge.Category.allCases {
            let ratio = Double(counts[category, default: 0]) / Double(draws)
            XCTAssertEqual(ratio, Double(category.selectionWeight) / 100, accuracy: 0.015)
        }
    }

    func testDisabledAndPreviousChallengesAreExcludedBeforeChoosingCategory() throws {
        let catalog = RioChallengeCatalog(challenges: [
            challenge("disabled", category: .silly, enabled: false),
            challenge("previous", category: .standard),
            challenge("available", category: .music),
        ])
        var random = SeededRandomGenerator(seed: 42)
        for _ in 0..<100 {
            XCTAssertEqual(catalog.next(excluding: "previous", using: &random)?.id, "available")
        }
    }

    func testEmptyDisabledAndSingleItemCatalogsCannotImmediatelyRepeat() {
        XCTAssertNil(RioChallengeCatalog(challenges: []).next())
        XCTAssertNil(RioChallengeCatalog(challenges: [challenge("off", enabled: false)]).next())
        let catalog = RioChallengeCatalog(challenges: [challenge("only")])
        XCTAssertEqual(catalog.next()?.id, "only")
        XCTAssertNil(catalog.next(excluding: "only"))
    }

    func testSmallTaskCategoryRoundTripsUsingContentKey() throws {
        let original = challenge("small", category: .smallTask)
        let data = try JSONEncoder().encode(original)
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("small_task"))
        XCTAssertEqual(try JSONDecoder().decode(RioChallenge.self, from: data), original)
    }

    func testExistingTauntRequestsDoNotOfferChallengesByDefault() {
        // 達成時・負けた時・オンボーディングの従来の閉じ方を変更しない。
        XCTAssertFalse(BlockedBehaviorTauntRequest(text: "ほんとに負けてきたの？w").offersChallenge)
        XCTAssertFalse(BlockedBehaviorTauntRequest(text: "ざこなのに頑張ったね♡").offersChallenge)
        XCTAssertTrue(BlockedBehaviorTauntRequest(text: "煽り", offersChallenge: true).offersChallenge)
    }

    private func challenge(
        _ id: String,
        category: RioChallenge.Category = .standard,
        enabled: Bool = true
    ) -> RioChallenge {
        RioChallenge(id: id, category: category, text: id, enabled: enabled)
    }
}

private struct SeededRandomGenerator: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed &+= 0x9E3779B97F4A7C15
        var value = seed
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
