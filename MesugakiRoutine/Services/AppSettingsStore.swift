import Foundation

/// アプリ全体の簡易設定。UserDefaultsに保存する。
enum AppSettingsStore {
    private static let userNameKey = "user_name"
    private static let notificationsEnabledKey = "notifications_enabled"
    private static let notificationDelayMinutesKey = "notification_delay_minutes"

    /// ユーザーネーム(例: 「だいすけ」)。未設定なら空文字。
    static var userName: String {
        get { UserDefaults.standard.string(forKey: userNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
    }

    /// 表示用の呼び名。呼称は常に「おにいさん」とする。
    /// 例: 「だいすけおにいさん」。名前未設定なら「おにいさん」。
    static var userDisplayName: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "おにいさん" : name + "おにいさん"
    }

    /// サボり通知を有効にするか。全ルーティン共通の設定。
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
