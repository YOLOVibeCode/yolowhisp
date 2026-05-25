import Foundation

/// Builds the concrete `PostProcessing` provider for a given config.
/// Shared by single AI-polish and dual-opinion merge so provider selection
/// lives in exactly one place.
public enum ProviderFactory {
    public static func make(config: PostProcessorConfig, session: URLSession = .shared) -> any PostProcessing {
        switch config.providerType {
        case .ollama:    return OllamaProvider(config: config, session: session)
        case .openai:    return OpenAIProvider(config: config, session: session)
        case .anthropic: return AnthropicProvider(config: config, session: session)
        case .custom:    return CustomProvider(config: config, session: session)
        }
    }
}
