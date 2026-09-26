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
    var id: String { lineId }

    var comment: InteractionComment {
        InteractionComment(id: lineId, text: text, weight: weight, active: active)
    }
}
