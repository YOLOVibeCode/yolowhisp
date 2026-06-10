import XCTest
@testable import YOLOWhisp

// MARK: - Mocks

/// Returns a canned hypothesis per sample regardless of audio content.
private final class StubTranscriber: Transcribing {
    let outputs: [String]
    private var index = 0
    init(outputs: [String]) { self.outputs = outputs }

    func transcribe(audioData: Data) async throws -> TranscriptionResult {
        let text = outputs[index % outputs.count]
        index += 1
        return TranscriptionResult(text: text, duration: 0.5, modelUsed: "stub")
    }
}

/// Applies a deterministic text transform (stand-in for AI polish).
private final class StubPolisher: PostProcessing {
    let providerName = "stub-polish"
    let transform: (String) -> String
    init(transform: @escaping (String) -> String) { self.transform = transform }
    func process(text: String) async throws -> String { transform(text) }
}

/// Always throws — simulates an unreachable AI provider.
private final class FailingPolisher: PostProcessing {
    let providerName = "failing-polish"
    struct Boom: Error {}
    func process(text: String) async throws -> String { throw Boom() }
}

// MARK: - Manifest

final class BenchmarkManifestTests: XCTestCase {
    func testParsesValidLines() {
        let tsv = "samples/a.aiff\tHello, world.\nsamples/b.aiff\tHow are you?"
        let samples = BenchmarkManifest.parse(tsv)
        XCTAssertEqual(samples, [
            BenchmarkSample(id: "samples/a.aiff", reference: "Hello, world."),
            BenchmarkSample(id: "samples/b.aiff", reference: "How are you?"),
        ])
    }

    func testReferenceMayContainTabsAfterFirst() {
        // Only the first tab splits; later tabs stay in the reference.
        let samples = BenchmarkManifest.parse("a.wav\tone\ttwo")
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].reference, "one\ttwo")
    }

    func testSkipsBlankAndMalformedLines() {
        let tsv = "\nsamples/a.aiff\tValid\nnotabhere\n\nsamples/b.aiff\t"
        let samples = BenchmarkManifest.parse(tsv)
        XCTAssertEqual(samples, [BenchmarkSample(id: "samples/a.aiff", reference: "Valid")])
    }
}

// MARK: - Runner

final class BenchmarkRunnerTests: XCTestCase {
    private func dummyAudio(_ sample: BenchmarkSample) -> (pcm: Data, seconds: Double) {
        (Data([0x01, 0x02]), 1.0)
    }

    func testRunnerProducesOneResultPerConfigSample() async throws {
        let samples = [
            BenchmarkSample(id: "a", reference: "hello world"),
            BenchmarkSample(id: "b", reference: "good morning"),
        ]
        let configs = [
            BenchmarkConfig(model: "m1", promptMode: "no-prompt",
                            transcriber: StubTranscriber(outputs: ["hello world", "good morning"])),
            BenchmarkConfig(model: "m2", promptMode: "no-prompt",
                            transcriber: StubTranscriber(outputs: ["hello word", "good evening"])),
        ]
        let runner = BenchmarkRunner(samples: samples, configs: configs, loadAudio: dummyAudio)
        let results = try await runner.run()

        XCTAssertEqual(results.count, 4)
        // m1 transcribes both perfectly -> WER 0.
        let m1 = results.filter { $0.model == "m1" }
        XCTAssertEqual(m1.map(\.rawScores.wer), [0, 0])
        // m2 has one word wrong in each -> WER > 0.
        let m2 = results.filter { $0.model == "m2" }
        XCTAssertTrue(m2.allSatisfy { $0.rawScores.wer > 0 })
        // No polisher -> no polish data.
        XCTAssertTrue(results.allSatisfy { !$0.didPolish })
    }

    func testPolisherImprovesScoreAndIsRecorded() async throws {
        let samples = [BenchmarkSample(id: "a", reference: "Hello, world.")]
        // Transcriber drops punctuation; polisher restores the exact reference.
        let configs = [BenchmarkConfig(model: "m1", promptMode: "no-prompt",
                                       transcriber: StubTranscriber(outputs: ["hello world"]))]
        let polisher = StubPolisher { _ in "Hello, world." }
        let runner = BenchmarkRunner(samples: samples, configs: configs,
                                     loadAudio: dummyAudio, polisher: polisher)
        let results = try await runner.run()

        let r = try XCTUnwrap(results.first)
        XCTAssertTrue(r.didPolish)
        XCTAssertEqual(r.polishedHypothesis, "Hello, world.")
        XCTAssertNil(r.polishError)
        // Polish recovered punctuation -> punctuation F1 improves to 1.
        let polishedPunct = try XCTUnwrap(r.polishedScores?.punctuationF1)
        XCTAssertEqual(polishedPunct, 1, accuracy: 1e-9)
        XCTAssertLessThan(r.rawScores.punctuationF1, 1)
    }

    func testPolishFailureIsCapturedNotThrown() async throws {
        let samples = [BenchmarkSample(id: "a", reference: "hello")]
        let configs = [BenchmarkConfig(model: "m1", promptMode: "no-prompt",
                                       transcriber: StubTranscriber(outputs: ["hello"]))]
        let runner = BenchmarkRunner(samples: samples, configs: configs,
                                     loadAudio: dummyAudio, polisher: FailingPolisher())
        let results = try await runner.run()

        let r = try XCTUnwrap(results.first)
        XCTAssertNil(r.polishedScores)
        XCTAssertNotNil(r.polishError)
    }

    func testEmptyPCMSampleIsSkipped() async throws {
        let samples = [BenchmarkSample(id: "a", reference: "hello")]
        let configs = [BenchmarkConfig(model: "m1", promptMode: "no-prompt",
                                       transcriber: StubTranscriber(outputs: ["hello"]))]
        let runner = BenchmarkRunner(samples: samples, configs: configs,
                                     loadAudio: { _ in (Data(), 0) })
        let results = try await runner.run()
        XCTAssertTrue(results.isEmpty)
    }
}

// MARK: - Report

final class BenchmarkReportTests: XCTestCase {
    private func result(model: String, wer: Double, punct: Double,
                        polishedWER: Double? = nil) -> BenchmarkRunResult {
        BenchmarkRunResult(
            model: model, promptMode: "no-prompt", sampleID: "a", reference: "ref",
            rawHypothesis: "hyp",
            rawScores: BenchmarkScores(wer: wer, semanticWER: wer, cer: wer, punctuationF1: punct),
            audioSeconds: 1, processingSeconds: 0.5,
            polishedHypothesis: polishedWER != nil ? "polished" : nil,
            polishedScores: polishedWER.map { BenchmarkScores(wer: $0, semanticWER: $0, cer: $0, punctuationF1: 1) },
            polishError: nil
        )
    }

    func testSummariesRankByWERAscending() {
        let results = [
            result(model: "worse", wer: 0.20, punct: 0.5),
            result(model: "better", wer: 0.05, punct: 0.9),
        ]
        let summaries = BenchmarkReport.summarize(results)
        XCTAssertEqual(summaries.first?.model, "better")
        XCTAssertEqual(summaries.last?.model, "worse")
    }

    func testMarkdownHasRankingHeaderAndBest() {
        let md = BenchmarkReport.markdown(results: [
            result(model: "alpha", wer: 0.1, punct: 0.8),
        ], sampleCount: 1)
        XCTAssertTrue(md.contains("# YOLOWhisp Model Accuracy Benchmark"))
        XCTAssertTrue(md.contains("| Rank | Model |"))
        XCTAssertTrue(md.contains("Best (raw): **alpha**"))
        // No polish data -> no AI Polish section.
        XCTAssertFalse(md.contains("## AI Polish"))
    }

    func testMarkdownIncludesPolishSectionWhenPresent() {
        let md = BenchmarkReport.markdown(results: [
            result(model: "alpha", wer: 0.20, punct: 0.5, polishedWER: 0.05),
        ], sampleCount: 1)
        XCTAssertTrue(md.contains("## AI Polish (final stage)"))
        XCTAssertTrue(md.contains("Best (after polish): **alpha**"))
        XCTAssertTrue(md.contains("Δ Sem WER"))
    }
}
