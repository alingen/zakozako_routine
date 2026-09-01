import Foundation

/// ユーザーの「よびかた」。みんなのざこ速報の表示に使う(将来キャラの呼びかけにも)。
enum UserHonorific: String, CaseIterable, Identifiable {
    case oniisan
    case oneesan
    case ojisan
    case obasan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .oniisan: return "おにいさん"
        case .oneesan: return "おねえさん"
        case .ojisan: return "おじさん"
        case .obasan: return "おばさん"
        }
    }
}

/// アプリ全体の簡易設定。UserDefaultsに保存する。
enum AppSettingsStore {
    private static let userNameKey = "user_name"
    private static let userHonorificKey = "user_honorific"
    private static let notificationsEnabledKey = "notifications_enabled"
    private static let notificationDelayMinutesKey = "notification_delay_minutes"

    /// ユーザーネーム(例: 「だいすけ」)。未設定なら空文字。
    static var userName: String {
        get { UserDefaults.standard.string(forKey: userNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
    }

    /// よびかた(おにいさん / おねえさん / おじさん / おばさん)。
    static var userHonorific: UserHonorific {
        get {
            UserDefaults.standard.string(forKey: userHonorificKey)
                .flatMap(UserHonorific.init(rawValue:)) ?? .oniisan
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userHonorificKey) }
    }

    /// 表示用の呼び名。ユーザーネーム + よびかた(例: 「だいすけおにいさん」。名前未設定なら「おにいさん」)。
    static var userDisplayName: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? userHonorific.displayName : name + userHonorific.displayName
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
