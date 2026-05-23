import Foundation

public enum ProviderType: String, Codable {
    case ollama
    case openai
    case anthropic
    case custom
}

public struct PostProcessorConfig {
    public let providerType: ProviderType
    public let modelName: String
    public let endpoint: String
    public let apiKey: String?
    public let customPrompt: String?

    public init(providerType: ProviderType, modelName: String, endpoint: String,
                apiKey: String? = nil, customPrompt: String? = nil) {
        self.providerType = providerType
        self.modelName = modelName
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.customPrompt = customPrompt
    }
}
