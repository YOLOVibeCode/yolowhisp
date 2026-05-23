import Foundation

public final class MajorityVoteConsensus: ConsensusStrategy {
    // Model priority order (largest = highest priority for tiebreaking)
    private static let modelPriority = ["large", "medium", "small", "base", "tiny"]

    public init() {}

    public func selectBest(from results: [TranscriptionResult]) -> TranscriptionResult {
        guard !results.isEmpty else { fatalError("No results") }
        guard results.count > 1 else { return results[0] }

        // Normalize text: trim, collapse whitespace, lowercase for comparison
        let normalized = results.map { (result: $0, key: normalize($0.text)) }

        // Group by normalized text
        var groups: [String: [TranscriptionResult]] = [:]
        for item in normalized {
            groups[item.key, default: []].append(item.result)
        }

        // Find largest group (majority)
        let sorted = groups.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            // Tiebreak: pick group containing the largest model
            return priority(of: a.value) > priority(of: b.value)
        }

        // From the winning group, return the result from the largest model
        let winner = sorted[0].value.sorted { priority(ofModel: $0.modelUsed) > priority(ofModel: $1.modelUsed) }
        return winner[0]
    }

    private func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private func priority(of results: [TranscriptionResult]) -> Int {
        results.map { priority(ofModel: $0.modelUsed) }.max() ?? 0
    }

    private func priority(ofModel name: String) -> Int {
        for (i, model) in Self.modelPriority.enumerated() {
            if name.contains(model) { return Self.modelPriority.count - i }
        }
        return 0
    }
}
