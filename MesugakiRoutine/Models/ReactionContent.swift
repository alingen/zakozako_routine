import Foundation

/// Google Sheets の本番タブから生成する定義。ユーザーの状態は保存しない。
struct ReactionCondition: Codable, Hashable, Identifiable {
    let conditionId: String
    let label: String
    let triggerType: String
    let conditionKey: String
    let `operator`: String
    let value: String
    let priority: Int
    let active: Bool
    var note: String? = nil
    var id: String { conditionId }
}

/// 空欄は通常コメント用。小さい吹き出し等の専用文を通常抽選へ混ぜない。
enum ReactionDisplayTarget: String, CaseIterable {
    case general
    case routineAdded = "home_routine_added"
    case unfinishedPeek = "home_peek_unfinished"
    case unfinishedTopPeek = "home_peek_unfinished_top"
    case idleAbove = "home_idle_above"
    case idleRight = "home_idle_right"
}

struct ReactionLine: Codable, Hashable, Identifiable {
    let lineId: String
    let conditionId: String
    let text: String
    // 将来の利用条件用。現在はどちらも抽選フィルターに使用しない。
    let strength: String
    let premiumOnly: Bool
    let weight: Int
    let active: Bool
    var note: String? = nil
    var displayTarget: String? = nil
    var id: String { lineId }

    func supports(_ target: ReactionDisplayTarget, routineTitle: String? = nil) -> Bool {
        let configured = displayTarget?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (configured.isEmpty ? "general" : configured) == target.rawValue
            && (!text.contains("{routine_title}") || routineTitle != nil)
    }

    func displayText(routineTitle: String? = nil) -> String {
        let formatted = text.replacingStoryTextMarkers()
        guard let routineTitle else { return formatted }
        return formatted.replacingOccurrences(of: "{routine_title}", with: routineTitle)
    }

    var comment: InteractionComment {
        InteractionComment(id: lineId, text: text, weight: weight, active: active)
    }
}
