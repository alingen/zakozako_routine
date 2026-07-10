import Foundation

/// 開発用の仕組み: `Secrets.local.json` (gitignore対象。存在しなくてもビルド・起動には影響しない) が
/// アプリバンドルに含まれていれば、初回起動時にそこからOpenAI APIキーを読み取ってKeychainへ1度だけ保存する。
/// これにより、APIキーをソースコードやGit管理下のファイルに一切書かずに実機/シミュレータでの動作確認ができる。
///
/// 本番の導線は `CharacterSettingsView` からユーザー自身がKeychainへ直接保存する方式であり、
/// これはあくまでローカル開発を楽にするための補助(Keychainに既に値があれば何もしない)。
enum LocalSecretsSeeder {
    private struct SecretsFile: Decodable {
        let openAIAPIKey: String?
    }

    static func seedIfNeeded() {
        guard KeychainService.load(key: KeychainService.openAIAPIKeyAccount) == nil else { return }
        guard let url = Bundle.main.url(forResource: "Secrets.local", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let secrets = try? JSONDecoder().decode(SecretsFile.self, from: data),
              let apiKey = secrets.openAIAPIKey, !apiKey.isEmpty else { return }
        KeychainService.save(key: KeychainService.openAIAPIKeyAccount, value: apiKey)
    }
}
