import SwiftUI

/// アプリ全体の配色（2026-09-01 確定）。用途ベースのセマンティックな名前で参照する。
/// ライト/ダーク別の値は未定義（単一値）。
enum AppColor {
    /// 主要ボタン、選択中、莉央の象徴色。
    static let primary = Color(hex: 0xD73A5A)
    /// 会話吹き出し、カードの強調。
    static let primarySoft = Color(hex: 0xF8D5DC)
    /// イベント、信頼度、特別感。
    static let secondary = Color(hex: 0x735ECF)
    /// 達成、スタンプ、小物。
    static let accent = Color(hex: 0xFFD166)
    /// アプリ背景、部屋の壁。
    static let background = Color(hex: 0xFFF7F3)
    /// カード、入力欄。
    static let surface = Color(hex: 0xFFFFFF)
    /// 本文、見出し。
    static let text = Color(hex: 0x352C32)
    /// 補足、未選択。
    static let muted = Color(hex: 0x81737A)
    /// 区切り線。
    static let border = Color(hex: 0xEADCE0)
    /// ルーティン完了。
    static let success = Color(hex: 0x3F8F70)
    /// 注意、継続危機。
    static let warning = Color(hex: 0xB66A13)
    /// 失敗、削除。
    static let error = Color(hex: 0xB93847)
}
