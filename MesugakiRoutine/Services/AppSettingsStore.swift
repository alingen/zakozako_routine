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

/// ユーザーの「よびかた」。キャラクターの呼びかけ・みんなのざこ速報の表示に使う。
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

/// アプリ全体の簡易設定。秘密情報ではないためUserDefaultsに保存する(APIキー等はKeychainServiceを使う)。
enum AppSettingsStore {
    private static let completionPhraseKey = "voice_completion_phrase"
    private static let uiModeKey = "app_ui_mode"
    private static let userNicknameKey = "user_nickname"
    private static let userNameKey = "user_name"
    private static let userHonorificKey = "user_honorific"
    private static let notificationsEnabledKey = "notifications_enabled"
    private static let notificationDelayMinutesKey = "notification_delay_minutes"
    private static let blockedBehaviorProtectedCountKey = "blocked_behavior_protected_count"

    /// ルーティン中のテキスト入力でこの発言(部分一致)が検出されたら、現在のステップを完了として次へ進める。
    static var completionPhrase: String {
        get { UserDefaults.standard.string(forKey: completionPhraseKey) ?? "できた" }
        set { UserDefaults.standard.set(newValue, forKey: completionPhraseKey) }
    }

    static var uiMode: AppUIMode {
        get { UserDefaults.standard.string(forKey: uiModeKey).flatMap(AppUIMode.init(rawValue:)) ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: uiModeKey) }
    }

    /// ユーザーネーム(例: 「だいすけ」)。未設定なら空文字。
    static var userName: String {
        get { UserDefaults.standard.string(forKey: userNameKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
    }

    /// よびかた(おにいさん / おねえさん / おじさん / おばさん)。
    static var userHonorific: UserHonorific {
        get {
            if let raw = UserDefaults.standard.string(forKey: userHonorificKey),
               let honorific = UserHonorific(rawValue: raw) {
                return honorific
            }
            // レガシー: 旧「呼び名」フリーテキストが よびかた と一致すれば引き継ぐ
            let legacy = UserDefaults.standard.string(forKey: userNicknameKey) ?? ""
            return UserHonorific.allCases.first { $0.displayName == legacy } ?? .oniisan
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: userHonorificKey) }
    }

    /// キャラクターがユーザーを呼ぶ時の呼び名。ユーザーネーム + よびかた から組み立てる
    /// (例: 「だいすけおにいさん」。ユーザーネーム未設定なら「おにいさん」)。空文字にはならない。
    static var userNickname: String {
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? userHonorific.displayName : name + userHonorific.displayName
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

    /// 「やらないこと」を「まもれた」と記録した累積回数。イベント解放条件で参照する。
    static var blockedBehaviorProtectedCount: Int {
        get { UserDefaults.standard.integer(forKey: blockedBehaviorProtectedCountKey) }
        set { UserDefaults.standard.set(newValue, forKey: blockedBehaviorProtectedCountKey) }
    }
}
