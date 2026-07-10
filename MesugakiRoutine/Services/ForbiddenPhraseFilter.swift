import Foundation

/// 禁止表現を除去する簡易フィルタ。ローカル生成・AI生成のどちらの出力に対しても同じ場所でガードする。
enum ForbiddenPhraseFilter {
    static func apply(_ text: String, forbidden: [String]) -> String {
        var result = text
        for phrase in forbidden where !phrase.isEmpty {
            result = result.replacingOccurrences(of: phrase, with: "")
        }
        return result
    }
}
