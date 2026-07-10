import Foundation

/// アプリ全体の簡易設定。秘密情報ではないためUserDefaultsに保存する(APIキー等はKeychainServiceを使う)。
enum AppSettingsStore {
    private static let completionPhraseKey = "voice_completion_phrase"

    /// 音声/自由入力でこの発言(部分一致)が検出されたら、現在のステップを完了として次へ進める。
    static var completionPhrase: String {
        get { UserDefaults.standard.string(forKey: completionPhraseKey) ?? "できた" }
        set { UserDefaults.standard.set(newValue, forKey: completionPhraseKey) }
    }
}
