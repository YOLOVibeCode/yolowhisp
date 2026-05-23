import Foundation

public final class CustomProvider: PostProcessing {
    public let providerName = "Custom"
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

        if let apiKey = config.apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let body: [String: Any] = [
            "text": text,
            "prompt": config.customPrompt ?? ""
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PostProcessError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PostProcessError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Try JSON {"result": "text"} first, fall back to raw text
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["result"] as? String {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let rawText = String(data: data, encoding: .utf8) else {
            throw PostProcessError.invalidResponse
        }
        return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
