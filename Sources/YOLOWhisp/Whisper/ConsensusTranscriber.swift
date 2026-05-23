import Foundation

public final class ConsensusTranscriber: Transcribing {
    private let transcribers: [any Transcribing]
    private let strategy: any ConsensusStrategy

    public init(transcribers: [any Transcribing], strategy: any ConsensusStrategy) {
        self.transcribers = transcribers
        self.strategy = strategy
    }

    public func transcribe(audioData: Data) async throws -> TranscriptionResult {
        // Run all transcribers in parallel
        try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
            for transcriber in transcribers {
                group.addTask {
                    try await transcriber.transcribe(audioData: audioData)
                }
            }

            var results: [TranscriptionResult] = []
            for try await result in group {
                results.append(result)
            }

            return strategy.selectBest(from: results)
        }
    }
}
