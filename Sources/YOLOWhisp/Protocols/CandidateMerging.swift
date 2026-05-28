import Foundation

/// Merges multiple transcription candidates into one result (e.g. via an LLM).
/// A narrow interface so DictationController depends on the capability, not the
/// concrete DualOpinionPolisher — and so it can be mocked in tests.
public protocol CandidateMerging {
    func merge(candidates: [String]) async throws -> String
}
