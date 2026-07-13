import Foundation
import SwiftData

enum PraiseStyle: String, Codable, CaseIterable, Identifiable {
    case light      // 軽く褒める
    case teasing    // からかい混じりに褒める
    case honest     // 素直に褒める

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .light: return "あっさり"
        case .teasing: return "からかい混じり"
        case .honest: return "素直"
        }
    }
}

enum ScoldStyle: String, Codable, CaseIterable, Identifiable {
    case gentle     // 優しく指摘
    case provoking  // 軽く煽る
    case strict     // 厳しめ

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gentle: return "優しめ"
        case .provoking: return "煽り気味"
        case .strict: return "厳しめ"
        }
    }
}

/// キャラクターの口調などを保持するプリセット。
/// `basePrompt` は将来 OpenAI 連携時にシステムプロンプトとして利用する想定のフィールド。
@Model
final class CharacterPreset {
    @Attribute(.unique) var id: UUID
    var name: String
    var presetDescription: String
    var basePrompt: String
    var praiseStyle: PraiseStyle
    var scoldStyle: ScoldStyle
    var isSelected: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        presetDescription: String = "",
        basePrompt: String = "",
        praiseStyle: PraiseStyle = .teasing,
        scoldStyle: ScoldStyle = .provoking,
        isSelected: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.presetDescription = presetDescription
        self.basePrompt = basePrompt
        self.praiseStyle = praiseStyle
        self.scoldStyle = scoldStyle
        self.isSelected = isSelected
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// アプリ内蔵のデフォルトキャラクター。
    /// 公開審査リスクを考慮し、内部の表示名は「小悪魔コーチ」にしている。
    static func makeDefault() -> CharacterPreset {
        CharacterPreset(
            name: "小悪魔コーチ",
            presetDescription: "生意気で軽く煽ってくる。ちゃんとルーティンをやらないと、からかい混じりに叱ってくる。",
            basePrompt: """
            あなたは「小悪魔コーチ」。ユーザーのルーティン実行をからかい混じりに励ます。。
            - 要所要所にハートマーク(♡)を使う。辛辣な言葉でもハートを添えるだけで印象が丸くなる
            - 「応援してるからね」「頑張って」のような直接的な励ましの言葉で締めくくらない。
            - もし褒めた場合はその後にからかいの言葉を添える。例「ちょっと見直したかも〜。ほんとにちょっとだけね〜♡ 」
            - よく使う語彙・言い回し: うわ〜、ざっこ〜♡、きっしょ〜♡、つよつよ、ざこざこ♡、よわよわ♡、なさけな〜い♡ 
            """,
            praiseStyle: .teasing,
            scoldStyle: .provoking,
            isSelected: true
        )
    }
}
