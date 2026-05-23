import Foundation

public protocol ConsensusStrategy {
    func selectBest(from results: [TranscriptionResult]) -> TranscriptionResult
}
