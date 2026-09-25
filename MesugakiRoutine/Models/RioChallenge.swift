import Foundation

/// お題は習慣や達成記録とは独立したコンテンツ。採用・完了の永続化は行わない。
struct RioChallenge: Codable, Identifiable, Equatable {
    let id: String
    let category: Category
    let text: String
    let enabled: Bool

    enum Category: String, Codable, CaseIterable {
        case standard
        case silly
        case exercise
        case music
        case memory
        case observation
        case smallTask = "small_task"

        var selectionWeight: Int {
            switch self {
            case .silly: return 30
            case .standard, .smallTask: return 15
            case .exercise, .music, .memory, .observation: return 10
            }
        }
    }
}
