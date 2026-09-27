import Foundation

/// rio_lines は固定案内・通知・お題の正本。状況別の反応は reaction_lines を参照する。
struct RioLine: Codable, Hashable, Identifiable {
    let lineId: String
    let groupId: String
    let text: String
    let weight: Int
    let active: Bool
    var note: String? = nil
    var id: String { lineId }

    func displayText(routineTitle: String? = nil) -> String {
        // 入力された約束名に含まれる [br] 等はコマンドとして解釈しない。
        let formatted = text.replacingStoryTextMarkers()
        guard let routineTitle else { return formatted }
        return formatted.replacingOccurrences(of: "{routine_title}", with: routineTitle)
    }
}

enum RioCopy {
    static let bundledLines = (try? StoryContentRepository().rioLines) ?? []

    static func text(_ id: String, routineTitle: String? = nil) -> String {
        bundledLines.first { $0.id == id }?.displayText(routineTitle: routineTitle) ?? ""
    }

    static func lines(group: String) -> [String] {
        bundledLines.filter { $0.groupId == group }.map { $0.displayText() }
    }

    static func random(group: String) -> String? {
        InteractionCommentSelector.select(
            from: bundledLines.filter { $0.groupId == group }.map {
                InteractionComment(id: $0.id, text: $0.text, weight: $0.weight, active: $0.active)
            }, touchArea: "character"
        )?.displayText
    }

    /// グループ内から重み付きで1件選び、`{routine_title}` を約束名に置き換える。
    static func random(group: String, routineTitle: String) -> String? {
        let lines = bundledLines.filter { $0.groupId == group }
        let selected = InteractionCommentSelector.select(
            from: lines.map {
                InteractionComment(id: $0.id, text: $0.text, weight: $0.weight, active: $0.active)
            }, touchArea: "character"
        )
        return lines.first { $0.id == selected?.id }?.displayText(routineTitle: routineTitle)
    }
}
