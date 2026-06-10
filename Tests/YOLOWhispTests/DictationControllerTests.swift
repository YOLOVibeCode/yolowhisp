import XCTest
@testable import YOLOWhisp

// MARK: - Mocks

final class MockAudioCapture: AudioCapturing {
    var isCapturing: Bool = false
    var startCaptureCalled = false
    var stopCaptureCalled = false
    var stubbedData = Data([0x01, 0x02, 0x03])

    func startCapture() {
        startCaptureCalled = true
        isCapturing = true
    }

    func stopCapture() -> Data {
        stopCaptureCalled = true
        isCapturing = false
        return stubbedData
    }
}

final class MockTranscriber: Transcribing {
    var receivedAudioData: Data?
    var stubbedResult = TranscriptionResult(text: "hello world", duration: 1.5, modelUsed: "tiny")
    var shouldThrow = false

    func transcribe(audioData: Data) async throws -> TranscriptionResult {
        receivedAudioData = audioData
        if shouldThrow { throw NSError(domain: "test", code: 1) }
        return stubbedResult
    }
}

final class MockTextOutput: TextOutputting {
    var mode: OutputMode = .simulatedKeystrokes
    var outputCalled = false
    var receivedText: String?

    func output(text: String) async throws {
        outputCalled = true
        receivedText = text
    }
}

final class MockHistoryStore: HistoryStoring {
    var savedEntry: HistoryEntry?
    var saveCalled = false

    func save(entry: HistoryEntry) throws {
        saveCalled = true
        savedEntry = entry
    }

    func search(query: String) throws -> [HistoryEntry] { [] }
    func delete(id: UUID) throws {}
    func entries(limit: Int) throws -> [HistoryEntry] { [] }
}

final class MockPostProcessor: PostProcessing {
    var providerName: String = "mock"
    var processCalled = false
    var receivedText: String?
    var stubbedResult = "Hello, world."
    var shouldThrow = false

    func process(text: String) async throws -> String {
        processCalled = true
        receivedText = text
        if shouldThrow { throw NSError(domain: "postprocess", code: 1) }
        return stubbedResult
    }
}

final class MockMerger: CandidateMerging {
    var shouldThrow = false
    var mergeCalled = false
    var stubbedResult = "merged result"

    func merge(candidates: [String]) async throws -> String {
        mergeCalled = true
        if shouldThrow { throw NSError(domain: "merge", code: 1) }
        return stubbedResult
    }
}

final class MockConsensusStrategy: ConsensusStrategy {
    var selectCalled = false
    var receivedCount = 0
    let stubbed: TranscriptionResult

    init(stubbed: TranscriptionResult) { self.stubbed = stubbed }

    func selectBest(from results: [TranscriptionResult]) -> TranscriptionResult {
        selectCalled = true
        receivedCount = results.count
        return stubbed
    }
}

final class MockPillDisplay: PillDisplaying {
    var stateHistory: [PillState] = []
    var currentPosition: CGPoint = .zero
    var position: CGPoint {
        get { currentPosition }
        set { currentPosition = newValue }
    }

    func show() {}
    func hide() {}
    func setState(_ state: PillState) {
        stateHistory.append(state)
    }
}

// MARK: - Tests

final class DictationControllerTests: XCTestCase {
    private var audioCapture: MockAudioCapture!
    private var transcriber: MockTranscriber!
    private var textOutput: MockTextOutput!
    private var historyStore: MockHistoryStore!
    private var postProcessor: MockPostProcessor!
    private var pill: MockPillDisplay!
    private var controller: DictationController!

    override func setUp() {
        super.setUp()
        audioCapture = MockAudioCapture()
        transcriber = MockTranscriber()
        textOutput = MockTextOutput()
        historyStore = MockHistoryStore()
        postProcessor = MockPostProcessor()
        pill = MockPillDisplay()

        let outputManager = TextOutputManager(outputs: [.simulatedKeystrokes: textOutput])
        controller = DictationController(
            audioCapture: audioCapture,
            transcriber: transcriber,
            textOutputManager: outputManager,
            historyStore: historyStore,
            postProcessor: postProcessor,
            pill: pill
        )
        // Pin the frontmost-app providers to a known NON-remote app so these
        // pipeline tests are deterministic. Otherwise the live
        // NSWorkspace.frontmostApplication (e.g. an RDP client open on the dev's
        // machine) would route output to the auto-detected remote mode, which
        // isn't registered here. Remote routing is covered by RemoteSessionDetector
        // and TextOutput tests.
        controller.frontmostAppProvider = { "TextEdit" }
        controller.frontmostBundleIdProvider = { "com.apple.TextEdit" }
    }

    func testStartDictationBeginsCapture() {
        controller.startDictation()
        XCTAssertTrue(audioCapture.startCaptureCalled)
        XCTAssertTrue(controller.isActive)
    }

    func testStopDictationTranscribes() async {
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertEqual(transcriber.receivedAudioData, audioCapture.stubbedData)
    }

    func testStopDictationOutputsText() async {
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertTrue(textOutput.outputCalled)
        XCTAssertEqual(textOutput.receivedText, "hello world")
    }

    func testStopDictationSavesToHistory() async {
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertTrue(historyStore.saveCalled)
        XCTAssertEqual(historyStore.savedEntry?.rawText, "hello world")
    }

    func testPillStateTransitions() async {
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertEqual(pill.stateHistory, [.recording, .processing, .idle])
    }

    func testPostProcessingEnabled() async {
        controller.postProcessEnabled = true
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertTrue(postProcessor.processCalled)
    }

    func testPostProcessingDisabled() async {
        controller.postProcessEnabled = false
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertFalse(postProcessor.processCalled)
    }

    func testPostProcessedTextUsedForOutput() async {
        controller.postProcessEnabled = true
        postProcessor.stubbedResult = "Polished text."
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertEqual(textOutput.receivedText, "Polished text.")
    }

    func testHistoryEntryContainsRawAndProcessed() async {
        controller.postProcessEnabled = true
        postProcessor.stubbedResult = "Polished."
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertEqual(historyStore.savedEntry?.rawText, "hello world")
        XCTAssertEqual(historyStore.savedEntry?.processedText, "Polished.")
    }

    func testTranscriptionErrorResetsPill() async {
        transcriber.shouldThrow = true
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertEqual(pill.stateHistory.last, .idle)
        XCTAssertFalse(controller.isActive)
    }

    func testHistoryEntryContainsTargetApp() async {
        controller.frontmostAppProvider = { "TestApp" }
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertEqual(historyStore.savedEntry?.targetApp, "TestApp")
    }

    // Regression: the app builds the controller without a postProcessor and
    // injects one later via setupPostProcessor(). Verify a late-set processor
    // actually runs — previously AI Polish flipped a flag with no provider.
    func testPostProcessorInjectedAfterInitRuns() async {
        let outputManager = TextOutputManager(outputs: [.simulatedKeystrokes: textOutput])
        let bare = DictationController(
            audioCapture: audioCapture,
            transcriber: transcriber,
            textOutputManager: outputManager,
            historyStore: historyStore,
            pill: pill
        )
        bare.frontmostAppProvider = { "TextEdit" }
        bare.frontmostBundleIdProvider = { "com.apple.TextEdit" }
        let late = MockPostProcessor()
        late.stubbedResult = "Injected."
        bare.postProcessor = late
        bare.postProcessEnabled = true

        bare.startDictation()
        await bare.stopDictation()

        XCTAssertTrue(late.processCalled)
        XCTAssertEqual(textOutput.receivedText, "Injected.")
    }

    // Resilience: an optional polish step failing must NOT drop the dictation —
    // the raw transcription should still be typed and saved.
    func testPostProcessorFailureStillOutputsRawTranscription() async {
        controller.postProcessEnabled = true
        postProcessor.shouldThrow = true
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertEqual(textOutput.receivedText, "hello world")
        XCTAssertTrue(historyStore.saveCalled)
        XCTAssertNotNil(controller.lastRunInfo?.error)
    }

    // Regression: a silent/empty transcription must NOT run AI polish, type,
    // or save. Feeding empty text to a provider made it echo its system prompt,
    // which then got typed out as garbage.
    func testEmptyTranscriptionSkipsPolishOutputAndSave() async {
        transcriber.stubbedResult = TranscriptionResult(text: "   ", duration: 0.2, modelUsed: "tiny")
        controller.postProcessEnabled = true
        controller.startDictation()
        await controller.stopDictation()

        XCTAssertFalse(postProcessor.processCalled, "polish must not run on empty text")
        XCTAssertFalse(textOutput.outputCalled, "nothing should be typed")
        XCTAssertFalse(historyStore.saveCalled, "nothing should be saved")
        XCTAssertEqual(pill.stateHistory.last, .idle)
        XCTAssertFalse(controller.isActive)
    }

    // Defense: if a polish provider echoes its instructions (empty after trim is
    // the simplest case), fall back to the raw transcription rather than typing
    // the model's noise.
    func testPolishReturningEmptyFallsBackToRaw() async {
        controller.postProcessEnabled = true
        postProcessor.stubbedResult = "   "
        controller.startDictation()
        await controller.stopDictation()

        XCTAssertEqual(textOutput.receivedText, "hello world")
        XCTAssertNotNil(controller.lastRunInfo?.error)
    }

    // Resilience: a dual-opinion merge failure falls back to the primary candidate.
    func testDualMergeFailureFallsBackToPrimary() async {
        let second = MockTranscriber()
        second.stubbedResult = TranscriptionResult(text: "second version", duration: 1, modelUsed: "small")
        controller.secondTranscriber = second
        let merger = MockMerger()
        merger.shouldThrow = true
        controller.dualOpinionPolisher = merger

        controller.startDictation()
        await controller.stopDictation()

        XCTAssertTrue(merger.mergeCalled)
        XCTAssertEqual(textOutput.receivedText, "hello world") // primary candidate
        XCTAssertTrue(historyStore.saveCalled)
    }

    // Offline dual-model mode: two candidates, a consensus strategy, no
    // polisher → the strategy picks the winner and it gets typed.
    func testConsensusStrategyPicksWinnerForDualModel() async {
        let outputManager = TextOutputManager(outputs: [.simulatedKeystrokes: textOutput])
        let second = MockTranscriber()
        second.stubbedResult = TranscriptionResult(text: "second version", duration: 1.0, modelUsed: "small")
        let c = DictationController(
            audioCapture: audioCapture,
            transcriber: transcriber,
            textOutputManager: outputManager,
            historyStore: historyStore,
            pill: pill
        )
        c.frontmostAppProvider = { "TextEdit" }
        c.frontmostBundleIdProvider = { "com.apple.TextEdit" }
        c.secondTranscriber = second
        let pick = TranscriptionResult(text: "the chosen one", duration: 1.0, modelUsed: "small")
        let strategy = MockConsensusStrategy(stubbed: pick)
        c.consensusStrategy = strategy

        c.startDictation()
        await c.stopDictation()

        XCTAssertTrue(strategy.selectCalled)
        XCTAssertEqual(strategy.receivedCount, 2)
        XCTAssertEqual(textOutput.receivedText, "the chosen one")
    }
}
