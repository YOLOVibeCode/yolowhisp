import Foundation

public final class AnthropicProvider: PostProcessing {
    public let providerName = "Anthropic"
    private let config: PostProcessorConfig
    private let session: URLSession

    public init(config: PostProcessorConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func process(text: String) async throws -> String {
        guard let apiKey = config.apiKey, !apiKey.isEmpty else {
            throw PostProcessError.noAPIKey
        }

        let url = URL(string: config.endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let systemPrompt = config.customPrompt
            ?? "Fix punctuation, capitalization, and any misheard words. Return ONLY the corrected text."

        let body: [String: Any] = [
            "model": config.modelName,
            "max_tokens": 4096,
            "messages": [
                ["role": "user", "content": text]
            ],
            "system": systemPrompt
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostProcessError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PostProcessError.apiError("HTTP \(httpResponse.statusCode)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let resultText = first["text"] as? String else {
            throw PostProcessError.invalidResponse
        }
        return resultText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
