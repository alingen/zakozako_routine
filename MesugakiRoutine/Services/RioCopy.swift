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

    /// `{user_name}` は名前が空でも必ず置き換え、差し込みの記号を画面に出さない
    /// (「ざこの{user_name}おにいさん」は「ざこのおにいさん」になる)。
    func displayText(routineTitle: String? = nil, userName: String = "") -> String {
        // 入力された約束名・名前に含まれる [br] 等はコマンドとして解釈しない。
        var formatted = text.replacingStoryTextMarkers()
            .replacingOccurrences(
                of: "{user_name}",
                with: userName.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        if let routineTitle {
            formatted = formatted.replacingOccurrences(of: "{routine_title}", with: routineTitle)
        }
        return formatted
    }
}

enum RioCopy {
    static let bundledLines = (try? StoryContentRepository().rioLines) ?? []

    /// `userName` を省くと、保存済みの名前(設定画面の名前)を差し込む。
    /// 名前の保存前(オンボーディング中)は入力中の名前を渡す。
    static func text(_ id: String, routineTitle: String? = nil, userName: String? = nil) -> String {
        bundledLines.first { $0.id == id }?.displayText(
            routineTitle: routineTitle,
            userName: userName ?? AppSettingsStore.userName
        ) ?? ""
    }

    static func lines(group: String) -> [String] {
        bundledLines.filter { $0.groupId == group }
            .map { $0.displayText(userName: AppSettingsStore.userName) }
    }

    static func random(group: String) -> String? {
        selectedLine(group: group)?.displayText(userName: AppSettingsStore.userName)
    }

    /// グループ内から重み付きで1件選び、`{routine_title}` を約束名に置き換える。
    static func random(group: String, routineTitle: String) -> String? {
        selectedLine(group: group)?.displayText(
            routineTitle: routineTitle,
            userName: AppSettingsStore.userName
        )
    }

    private static func selectedLine(group: String) -> RioLine? {
        let lines = bundledLines.filter { $0.groupId == group }
        let selected = InteractionCommentSelector.select(
            from: lines.map {
                InteractionComment(id: $0.id, text: $0.text, weight: $0.weight, active: $0.active)
            }, touchArea: "character"
        )
        return lines.first { $0.id == selected?.id }
    }
}
