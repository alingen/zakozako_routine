import Foundation

/// イベント定義(EventDefinition)を、バンドルされた
/// `Resources/GeneratedScenarios/events.generated.json` から読み込む。
///
/// このJSONは Google スプレッドシート(正本)から `tools/scenario-sync` で自動生成されるため、
/// 直接編集しないこと。イベントを変更する時はスプレッドシートを編集し、同期コマンドを実行する。
struct EventCatalog {
    let allEvents: [EventDefinition]

    init() {
        allEvents = Self.loadAll()
    }

    func event(id: String) -> EventDefinition? {
        allEvents.first { $0.eventId == id }
    }

    func events(of kind: EventKind) -> [EventDefinition] {
        allEvents.filter { $0.eventType == kind }
    }

    private struct GeneratedBundle: Decodable {
        let events: [EventDefinition]
    }

    private static func loadAll() -> [EventDefinition] {
        guard let url = Bundle.main.url(forResource: "events.generated", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            assertionFailure("events.generated.json が見つからない(scenario-sync を実行しましたか)")
            return []
        }
        do {
            // 生成側で priority 昇順に並んでいる。配列順がそのまま解放判定の優先順になる。
            return try JSONDecoder().decode(GeneratedBundle.self, from: data).events
        } catch {
            assertionFailure("events.generated.json を解釈できない: \(error)")
            return []
        }
    }
}
