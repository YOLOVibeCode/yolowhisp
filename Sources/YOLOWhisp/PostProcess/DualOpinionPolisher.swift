import Foundation

/// Takes two transcription candidates and uses an LLM to merge them into
/// a single, well-punctuated result — the "second opinion" approach.
///
/// Creates its own provider instance with a merge-specific system prompt,
/// then sends both candidate texts for the LLM to adjudicate.
public final class DualOpinionPolisher: CandidateMerging {
    private let config: PostProcessorConfig
    private let session: URLSession

    public init(config: PostProcessorConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Merge multiple transcription candidates into one polished result.
    public func merge(candidates: [String]) async throws -> String {
        guard !candidates.isEmpty else { return "" }

        // Build the user message with labeled versions
        var userMessage: String
        if candidates.count == 1 {
            userMessage = candidates[0]
        } else {
            userMessage = candidates.enumerated().map { i, text in
                "VERSION \(i + 1):\n\(text)"
            }.joined(separator: "\n\n")
        }

        // Create a provider with the merge prompt as the system prompt
        let mergeConfig = PostProcessorConfig(
            providerType: config.providerType,
            modelName: config.modelName,
            endpoint: config.endpoint,
            apiKey: config.apiKey,
            customPrompt: candidates.count > 1 ? Self.mergePrompt : Self.singlePolishPrompt
        )

        let provider = ProviderFactory.make(config: mergeConfig, session: session)
        return try await provider.process(text: userMessage)
    }

    static let mergePrompt = """
        You are a transcription editor. You receive multiple versions of the same \
        spoken text from different speech recognition models. Produce a single final \
        version that:

        1. Picks the most accurate wording from whichever version got it right
        2. Has correct punctuation: periods, commas, question marks, exclamation marks, \
           colons, semicolons, apostrophes, em dashes
        3. Has proper capitalization (sentence starts, proper nouns, acronyms)
        4. Preserves the speaker's intended tone — questions stay questions, \
           exclamations stay exclamations, emphasis is kept
        5. Does NOT add, remove, or rephrase content — only fix punctuation and \
           pick the best wording between versions

        Return ONLY the final corrected text. No explanations, no labels, no quotes.
        """

    static let singlePolishPrompt = """
        You are a transcription editor. Fix the punctuation, capitalization, and any \
        obvious misheard words in the following transcription. Specifically:

        1. Add correct punctuation: periods, commas, question marks, exclamation marks, \
           colons, semicolons, apostrophes, em dashes
        2. Fix capitalization (sentence starts, proper nouns, acronyms)
        3. Preserve the speaker's intended tone — questions stay questions, \
           exclamations stay exclamations
        4. Do NOT add, remove, or rephrase content — only fix errors

        Return ONLY the corrected text. No explanations, no labels, no quotes.
        """
}
