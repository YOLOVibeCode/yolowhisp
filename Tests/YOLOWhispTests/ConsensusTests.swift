import Foundation
import Testing
@testable import YOLOWhisp

// MARK: - Mock Transcriber

private final class ConsensusMockTranscriber: Transcribing, @unchecked Sendable {
    let result: TranscriptionResult
    private(set) var receivedData: Data?

    init(text: String, model: String) {
        self.result = TranscriptionResult(text: text, duration: 0.5, modelUsed: model)
    }

    func transcribe(audioData: Data) async throws -> TranscriptionResult {
        receivedData = audioData
        return result
    }
}

// MARK: - MajorityVoteConsensus Tests

@Suite("MajorityVoteConsensus")
struct MajorityVoteConsensusTests {

    @Test("majority vote picks most common text")
    func testMajorityVotePicksMostCommon() {
        let consensus = MajorityVoteConsensus()
        let results = [
            TranscriptionResult(text: "hello world", duration: 0.5, modelUsed: "tiny"),
            TranscriptionResult(text: "hello world", duration: 0.6, modelUsed: "base"),
            TranscriptionResult(text: "hello world!", duration: 0.4, modelUsed: "small"),
        ]
        let best = consensus.selectBest(from: results)
        #expect(best.text == "hello world")
    }

    @Test("disagreement picks largest model")
    func testDisagreementPicksLargestModel() {
        let consensus = MajorityVoteConsensus()
        let results = [
            TranscriptionResult(text: "alpha", duration: 0.5, modelUsed: "tiny"),
            TranscriptionResult(text: "beta", duration: 0.5, modelUsed: "small"),
            TranscriptionResult(text: "gamma", duration: 0.5, modelUsed: "base"),
        ]
        let best = consensus.selectBest(from: results)
        #expect(best.text == "beta") // "small" has highest priority among the three
    }

    @Test("single result returned as-is")
    func testSingleResultReturnedAsIs() {
        let consensus = MajorityVoteConsensus()
        let result = TranscriptionResult(text: "only one", duration: 1.0, modelUsed: "tiny")
        let best = consensus.selectBest(from: [result])
        #expect(best.text == "only one")
        #expect(best.modelUsed == "tiny")
    }

    @Test("two results tie breaks on model size")
    func testTwoResultsTieBreaksOnModelSize() {
        let consensus = MajorityVoteConsensus()
        let results = [
            TranscriptionResult(text: "A", duration: 0.5, modelUsed: "tiny"),
            TranscriptionResult(text: "B", duration: 0.5, modelUsed: "small"),
        ]
        let best = consensus.selectBest(from: results)
        #expect(best.text == "B")
    }

    @Test("normalize handles whitespace")
    func testNormalizeHandlesWhitespace() {
        let consensus = MajorityVoteConsensus()
        let results = [
            TranscriptionResult(text: "  hello   world  ", duration: 0.5, modelUsed: "tiny"),
            TranscriptionResult(text: "hello world", duration: 0.5, modelUsed: "base"),
            TranscriptionResult(text: "different", duration: 0.5, modelUsed: "small"),
        ]
        let best = consensus.selectBest(from: results)
        // "hello world" and "  hello   world  " normalize the same → majority (2 vs 1)
        #expect(best.text.trimmingCharacters(in: .whitespacesAndNewlines).contains("hello world"))
    }
}

// MARK: - ConsensusTranscriber Tests

@Suite("ConsensusTranscriber")
struct ConsensusTranscriberTests {

    @Test("parallel transcription runs all models")
    func testParallelTranscriptionRunsAllModels() async throws {
        let mock1 = ConsensusMockTranscriber(text: "hello", model: "tiny")
        let mock2 = ConsensusMockTranscriber(text: "hello", model: "base")
        let mock3 = ConsensusMockTranscriber(text: "hello", model: "small")

        let consensus = ConsensusTranscriber(
            transcribers: [mock1, mock2, mock3],
            strategy: MajorityVoteConsensus()
        )

        let testData = Data("test audio".utf8)
        let _ = try await consensus.transcribe(audioData: testData)

        #expect(mock1.receivedData == testData)
        #expect(mock2.receivedData == testData)
        #expect(mock3.receivedData == testData)
    }

    @Test("conforms to Transcribing protocol")
    func testConsensusTranscriberConformsToProtocol() {
        let transcriber = ConsensusTranscriber(
            transcribers: [],
            strategy: MajorityVoteConsensus()
        )
        #expect(transcriber is any Transcribing)
    }
}
