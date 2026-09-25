import Foundation
import UIKit

/// 設定の「このアプリについて」「お問い合わせ」で使うアプリの情報。
enum AppInfo {
    /// お問い合わせ先。
    /// TODO: 公開前に正式な窓口へ差し替える(example.com は仮置き用の予約ドメイン)。
    static let supportEmail = "support@example.com"

    /// 「1.0 (1)」のような表示用バージョン。
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    /// 問い合わせメールの下書き。不具合の調査に要る情報だけを添える。
    @MainActor
    static func supportMailURL() -> URL? {
        let subject = "ザコルーティンへのお問い合わせ"
        let body = """


        ----
        アプリ: \(versionText)
        iOS: \(UIDevice.current.systemVersion)
        """
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
