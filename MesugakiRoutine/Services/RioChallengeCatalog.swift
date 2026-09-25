import Foundation

/// カテゴリを重み付きで選び、その中から1件を抽選する。登録件数に割合を左右させない。
struct RioChallengeCatalog {
    let challenges: [RioChallenge]

    static let bundled: RioChallengeCatalog = {
        do {
            return try load()
        } catch {
            assertionFailure("莉央のお題データを読み込めません: \(error)")
            return RioChallengeCatalog(challenges: [])
        }
    }()

    static func load(bundle: Bundle = .main) throws -> RioChallengeCatalog {
        guard let url = bundle.url(forResource: "rio_challenges", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let challenges = try JSONDecoder().decode([RioChallenge].self, from: Data(contentsOf: url))
        return RioChallengeCatalog(challenges: challenges)
    }

    func next(excluding previousID: String? = nil) -> RioChallenge? {
        var generator = SystemRandomNumberGenerator()
        return next(excluding: previousID, using: &generator)
    }

    func next<R: RandomNumberGenerator>(
        excluding previousID: String? = nil,
        using generator: inout R
    ) -> RioChallenge? {
        let candidates = challenges.filter { $0.enabled && $0.id != previousID }
        let categories = RioChallenge.Category.allCases.filter { category in
            candidates.contains { $0.category == category }
        }
        let totalWeight = categories.reduce(0) { $0 + $1.selectionWeight }
        guard totalWeight > 0 else { return nil }

        var draw = Int.random(in: 0..<totalWeight, using: &generator)
        for category in categories {
            if draw < category.selectionWeight {
                return candidates.filter { $0.category == category }.randomElement(using: &generator)
            }
            draw -= category.selectionWeight
        }
        return nil
    }
}
