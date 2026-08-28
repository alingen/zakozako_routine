import Foundation

/// イベントの種類。小イベント(LINE風UI・STEP 5)と大イベント(ギャルゲー風UI・STEP 6)を区別する。
enum EventKind: String, Codable {
    case small
    case big
}

/// イベントの解放条件。指定した項目を「すべて満たした」時に解放される(AND)。
/// nilの項目は条件なしとして扱う。巨大な条件式は作らず、この単純なAND合成で足りる想定。
///
/// 例:
/// - `{ "minTrust": 3 }` … 信頼度3以上
/// - `{ "minStreakDays": 3 }` … 3日継続
/// - `{ "minBlockedProtectedCount": 5 }` … やらないことを5回まもれた
/// - `{ "minTrust": 10, "minStreakDays": 7 }` … 信頼度10以上 かつ 7日継続
/// - `{ "requiredCompletedEventIds": ["evt_xxx"] }` … 特定イベント閲覧済み
struct EventCondition: Codable, Hashable {
    var minTrust: Int?
    var minStreakDays: Int?
    /// 「やらないこと」を守れた累積回数(AppSettingsStore.blockedBehaviorProtectedCount)。
    var minBlockedProtectedCount: Int?
    /// 「やらないこと」を卒業(14日達成)した個数。
    var minMasteredCount: Int?
    /// 関係性フェーズ(RelationshipState.phase)がこの値以上。
    var minRelationshipPhase: Int?
    /// これらのイベントを完了済みであること。
    var requiredCompletedEventIds: [String]?

    func isSatisfied(by metrics: ProgressMetrics) -> Bool {
        if let required = minTrust, metrics.trustPoints < required { return false }
        if let required = minStreakDays, metrics.streakDays < required { return false }
        if let required = minBlockedProtectedCount, metrics.blockedProtectedCount < required { return false }
        if let required = minMasteredCount, metrics.masteredCount < required { return false }
        if let required = minRelationshipPhase, metrics.relationshipPhase < required { return false }
        if let ids = requiredCompletedEventIds, !Set(ids).isSubset(of: metrics.completedEventIds) { return false }
        return true
    }

    /// デバッグ表示用の説明文。
    var summary: String {
        var parts: [String] = []
        if let v = minTrust { parts.append("信頼度\(v)+") }
        if let v = minStreakDays { parts.append("継続\(v)日") }
        if let v = minBlockedProtectedCount { parts.append("やらないこと\(v)回") }
        if let v = minMasteredCount { parts.append("卒業\(v)個") }
        if let v = minRelationshipPhase { parts.append("関係Phase\(v)+") }
        if let ids = requiredCompletedEventIds, !ids.isEmpty { parts.append("前提イベント\(ids.count)件") }
        return parts.isEmpty ? "条件なし" : parts.joined(separator: " & ")
    }
}

/// 1イベントの定義。内容(台本)は Google スプレッドシート(正本)から生成される
/// `Resources/GeneratedScenarios/events.generated.json` で管理する(直接編集しない)。
/// 解放状態・完了状態は `EventProgress` 側で永続化する(定義には含めない)。
/// 生成JSONには priority / repeatable / cooldownDays も含まれるが、synthesized Decodable は
/// 未知キーを無視するため、ここで宣言していないフィールドは安全に読み飛ばされる。
struct EventDefinition: Codable, Identifiable, Hashable {
    let eventId: String
    let eventType: EventKind
    /// イベント名(解放通知や一覧の表示に使う。キャラのセリフではない)。
    let title: String
    let unlockConditions: EventCondition
    /// 会話台本。小イベントは今日の会話と同じ再生エンジン(ScriptPlayer)で流す。
    let messages: [ScriptMessage]

    /// 大イベントの初期背景画像(Assets)。各メッセージの `background` で途中変更できる。
    let background: String?
    /// 大イベント完了時に、関係性フェーズをこの値まで進める(現在より高い場合のみ)。
    let advancesToPhase: Int?

    var id: String { eventId }
}
