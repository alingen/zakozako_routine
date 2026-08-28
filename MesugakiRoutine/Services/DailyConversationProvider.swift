import Foundation

/// 「今日の会話」の台本を、バンドルされた `Resources/GeneratedScenarios/daily_conversations.generated.json`
/// から読み込む。
///
/// このJSONは Google スプレッドシート(正本)から `tools/scenario-sync` で自動生成されるため、
/// 直接編集しないこと。会話を変更する時はスプレッドシートを編集し、同期コマンドを実行する。
struct DailyConversationProvider {
    private let scenarios: [Scenario]

    init() {
        scenarios = Self.load()
    }

    /// 用意されている「今日の会話」の本数。
    var availableDayCount: Int { max(scenarios.count, 1) }

    /// 指定インデックス(0始まり)の台本を返す。用意した本数を超えたら、当面は最終話を繰り返す。
    func script(forIndex index: Int) -> ConversationScript? {
        guard !scenarios.isEmpty else {
            assertionFailure("今日の会話の台本が0件")
            return nil
        }
        let clampedIndex = min(max(index, 0), scenarios.count - 1)
        return ConversationScript(messages: scenarios[clampedIndex].messages)
    }

    // MARK: - 生成JSONのデコード

    private struct GeneratedBundle: Decodable {
        let scenarios: [Scenario]
    }

    private struct Scenario: Decodable {
        let scenarioId: String
        let dayIndex: Int
        let messages: [ScriptMessage]
    }

    private static func load() -> [Scenario] {
        guard let url = Bundle.main.url(forResource: "daily_conversations.generated", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("daily_conversations.generated.json が見つからない(scenario-sync を実行しましたか)")
            return []
        }
        do {
            return try JSONDecoder()
                .decode(GeneratedBundle.self, from: data)
                .scenarios
                .sorted { $0.dayIndex < $1.dayIndex }
        } catch {
            assertionFailure("daily_conversations.generated.json を解釈できない: \(error)")
            return []
        }
    }
}
