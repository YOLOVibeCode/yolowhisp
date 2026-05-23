import Foundation

public final class OpenAIProvider: PostProcessing {
    public let providerName = "OpenAI"
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
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let systemPrompt = config.customPrompt
            ?? "Fix punctuation, capitalization, and any misheard words. Return ONLY the corrected text."

        let body: [String: Any] = [
            "model": config.modelName,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
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
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw PostProcessError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
