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

    func process(text: String) async throws -> String {
        processCalled = true
        receivedText = text
        return stubbedResult
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
}
