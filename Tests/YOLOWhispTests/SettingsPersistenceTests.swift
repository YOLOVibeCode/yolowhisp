import XCTest
@testable import YOLOWhisp

final class SettingsPersistenceTests: XCTestCase {
    private var controller: DictationController!
    private var historyStore: MockHistoryStore!
    private var postProcessor: MockPostProcessor!
    private var textOutput: MockTextOutput!

    override func setUp() {
        super.setUp()
        let audioCapture = MockAudioCapture()
        let transcriber = MockTranscriber()
        textOutput = MockTextOutput()
        historyStore = MockHistoryStore()
        postProcessor = MockPostProcessor()
        let pill = MockPillDisplay()

        let outputManager = TextOutputManager(outputs: [
            .simulatedKeystrokes: textOutput,
            .clipboardPaste: textOutput,
        ])
        controller = DictationController(
            audioCapture: audioCapture,
            transcriber: transcriber,
            textOutputManager: outputManager,
            historyStore: historyStore,
            postProcessor: postProcessor,
            pill: pill
        )
    }

    func testOutputModeDefaultIsSimulatedKeystrokes() {
        XCTAssertEqual(controller.outputMode, .simulatedKeystrokes)
    }

    func testOutputModeChangePersists() {
        controller.outputMode = .clipboardPaste
        XCTAssertEqual(controller.outputMode, .clipboardPaste)
    }

    func testPostProcessEnabledDefault() {
        XCTAssertFalse(controller.postProcessEnabled)
    }

    func testPostProcessEnabledToggle() async {
        controller.postProcessEnabled = true
        controller.startDictation()
        await controller.stopDictation()
        XCTAssertTrue(postProcessor.processCalled)
    }
}
