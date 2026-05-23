import Foundation

public final class OllamaProvider: PostProcessing {
    public let providerName = "Ollama"
    private let config: PostProcessorConfig
    private let session: URLSession

    public init(config: PostProcessorConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func process(text: String) async throws -> String {
        let url = URL(string: config.endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let prompt = config.customPrompt
            ?? "Fix punctuation, capitalization, and any misheard words. Return ONLY the corrected text."

        let body: [String: Any] = [
            "model": config.modelName,
            "prompt": "\(prompt)\n\n\(text)",
            "stream": false
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
              let result = json["response"] as? String else {
            throw PostProcessError.invalidResponse
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
