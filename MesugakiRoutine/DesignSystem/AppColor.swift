import SwiftUI

/// アプリ全体の配色（2026-09-01 確定）。用途ベースのセマンティックな名前で参照する。
/// 役割と使ってよい組み合わせは CLAUDE.md の「色」を正とする。
/// ライト/ダーク別の値は未定義（単一値）。
enum AppColor {
    // MARK: - ブランドカラー

    /// Primary。「今押すべき操作」と莉央の象徴色(完了ボタン、追加、NEW、名札)。
    static let primary = Color(hex: 0xD73A5A)
    /// Pink。莉央の吹き出し、アイコンの丸い地。
    static let primarySoft = Color(hex: 0xF8D5DC)
    /// Purple。達成(完了した約束の円とチェック、達成のお知らせ)、ストーリー・思い出など特別感のあるもの。
    static let secondary = Color(hex: 0x735ECF)
    /// Yellow。連続記録の炎などの飾り。文字や単独のアイコンには使わない(白地で1.44:1)。
    static let accent = Color(hex: 0xFFD166)
    /// Background。画面の地。
    static let background = Color(hex: 0xFFF7F3)
    /// Surface。カード、入力欄、読みもの画面の地。
    static let surface = Color(hex: 0xFFFFFF)
    /// Text。本文、見出し。
    static let text = Color(hex: 0x352C32)
    /// Muted。補足、未選択。文字に使うのは白地(surface)の上だけ(背景色の上では4.25:1で不足)。
    static let muted = Color(hex: 0x81737A)
    /// Border。枠線、区切り線。
    static let border = Color(hex: 0xEADCE0)

    // MARK: - 状態表示専用

    /// 達成・完了の状態。アイコンに使い、文字には使わない(白地で3.91:1)。
    static let success = Color(hex: 0x3F8F70)
    /// 注意・警告の状態。アイコンに使い、文字には使わない(白地で4.15:1)。
    static let warning = Color(hex: 0xB66A13)
    /// 失敗・削除・エラーの状態。文字にも使える(白地で5.65:1)。
    static let error = Color(hex: 0xB93847)
}
