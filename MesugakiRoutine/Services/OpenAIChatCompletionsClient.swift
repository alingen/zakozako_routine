import Foundation

/// OpenAI Chat Completions API (`/v1/chat/completions`) を叩く最小限のネットワーククライアント。
/// 将来 Realtime API に対応する際は、これとは別に WebSocket ベースのクライアントを用意する想定。
struct OpenAIChatMessage: Codable {
    let role: String
    let content: String
}

enum OpenAIClientError: Error {
    case missingAPIKey
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case emptyChoice
}

final class OpenAIChatCompletionsClient {
    private struct Request: Encodable {
        let model: String
        let messages: [OpenAIChatMessage]
        let temperature: Double
        let max_tokens: Int
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            let message: OpenAIChatMessage
        }
        let choices: [Choice]
    }

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(
        messages: [OpenAIChatMessage],
        apiKey: String,
        model: String,
        temperature: Double = 0.8,
        maxTokens: Int = 150
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw OpenAIClientError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            Request(model: model, messages: messages, temperature: temperature, max_tokens: maxTokens)
        )

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw OpenAIClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw OpenAIClientError.httpError(statusCode: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let text = decoded.choices.first?.message.content else {
            throw OpenAIClientError.emptyChoice
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
