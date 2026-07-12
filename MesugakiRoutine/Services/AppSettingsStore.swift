import Foundation

/// UIの見た目の方向性。現状は設定を保持するだけで、見た目自体はまだ切り替わらない
/// (将来「小悪魔モード」用のポップなUIを実装する際にここを参照する想定)。
enum AppUIMode: String, CaseIterable, Identifiable {
    case normal
    case playful

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .normal: return "通常擬態モード"
        case .playful: return "小悪魔モード"
        }
    }

    var description: String {
        switch self {
        case .normal: return "落ち着いた見た目のモードです。"
        case .playful: return "かわいくポップな見た目のモードです(準備中)。"
        }
    }
}

/// アプリ全体の簡易設定。秘密情報ではないためUserDefaultsに保存する(APIキー等はKeychainServiceを使う)。
enum AppSettingsStore {
    private static let completionPhraseKey = "voice_completion_phrase"
    private static let uiModeKey = "app_ui_mode"
    private static let userNicknameKey = "user_nickname"
    private static let notificationsEnabledKey = "notifications_enabled"
    private static let notificationDelayMinutesKey = "notification_delay_minutes"

    /// 音声/自由入力でこの発言(部分一致)が検出されたら、現在のステップを完了として次へ進める。
    static var completionPhrase: String {
        get { UserDefaults.standard.string(forKey: completionPhraseKey) ?? "できた" }
        set { UserDefaults.standard.set(newValue, forKey: completionPhraseKey) }
    }

    static var uiMode: AppUIMode {
        get { UserDefaults.standard.string(forKey: uiModeKey).flatMap(AppUIMode.init(rawValue:)) ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: uiModeKey) }
    }

    /// キャラクターがユーザーを呼ぶ時の呼び名。空文字なら特に呼びかけない。
    static var userNickname: String {
        get { UserDefaults.standard.string(forKey: userNicknameKey) ?? "おにいさん" }
        set { UserDefaults.standard.set(newValue, forKey: userNicknameKey) }
    }

    /// サボり通知を有効にするか。全ルーティン共通の設定(ルーティンごとの個別設定は持たない)。
    static var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: notificationsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: notificationsEnabledKey) }
    }

    /// 各ルーティンの開始予定時刻から何分後に、まだ終わっていなければ通知するか。全ルーティン共通。
    static var notificationDelayMinutes: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: notificationDelayMinutesKey)
            return value == 0 ? 30 : value
        }
        set { UserDefaults.standard.set(newValue, forKey: notificationDelayMinutesKey) }
    }
}
