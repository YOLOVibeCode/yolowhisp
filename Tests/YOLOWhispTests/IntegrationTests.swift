import XCTest
@testable import YOLOWhisp

/// End-to-end integration test using real whisper-cli but pre-recorded audio.
/// Requires: whisper-cli installed, ggml-small.bin model available.
/// These tests are skipped in CI (no whisper-cli).
final class IntegrationTests: XCTestCase {

    private let whisperPath = "/opt/homebrew/bin/whisper-cli"
    private let modelPaths = [
        "/Users/admin/Dev/YOLOProjects/yolowhisp/benchmark/models",
        "/opt/homebrew/share/whisper-cpp/models",
    ]

    private func skipIfNoWhisper() throws {
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: whisperPath),
            "whisper-cli not installed"
        )
    }

    // MARK: - Full Pipeline Test

    func testFullPipelineWithSyntheticAudio() async throws {
        try skipIfNoWhisper()

        // 1. Create synthetic audio (1 second of silence — whisper will return empty/noise)
        let sampleCount = 16000 // 1 second at 16kHz
        let pcmData = Data(repeating: 0, count: sampleCount * 2) // 16-bit silence

        // 2. Set up real components
        let modelManager = ModelManager(searchPaths: modelPaths)
        let models = modelManager.availableModels()
        try XCTSkipIf(models.isEmpty, "No whisper models found")

        // Use smallest available model for speed
        let model = models.sorted(by: { $0.size < $1.size }).first!
        try modelManager.loadModel(model)

        let engine = WhisperEngine(
            whisperPath: whisperPath,
            modelManager: modelManager
        )

        // 3. Transcribe
        let result = try await engine.transcribe(audioData: pcmData)
        XCTAssertNotNil(result.timestamp)
        XCTAssertEqual(result.modelUsed, model.name)

        // 4. Save to history
        let store = HistoryStore() // in-memory
        let entry = HistoryEntry(
            rawText: result.text,
            duration: result.duration,
            modelUsed: result.modelUsed
        )
        try store.save(entry: entry)

        let entries = try store.entries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].rawText, result.text)
    }

    // MARK: - Model Manager Integration

    func testModelManagerFindsInstalledModels() throws {
        try skipIfNoWhisper()

        let manager = ModelManager(searchPaths: modelPaths)
        let models = manager.availableModels()
        try XCTSkipIf(models.isEmpty, "No models in search paths")

        for model in models {
            XCTAssertTrue(model.name.contains("ggml-") || !model.name.isEmpty)
            XCTAssertGreaterThan(model.size, 0)
            XCTAssertTrue(FileManager.default.fileExists(atPath: model.path))
        }
    }

    // MARK: - Whisper Output Parsing

    func testParseRealWhisperOutput() {
        let sampleOutput = """
        [00:00:00.000 --> 00:00:03.000]   Hello, this is a test of the YOLOWhisp system.
        [00:00:03.000 --> 00:00:06.000]   It should handle punctuation, capitalization, and more.
        """

        let parsed = WhisperEngine.parseOutput(sampleOutput)
        XCTAssertTrue(parsed.contains("Hello"))
        XCTAssertTrue(parsed.contains("YOLOWhisp"))
        XCTAssertTrue(parsed.contains("punctuation"))
    }

    // MARK: - Text Output Integration

    func testClipboardRoundtrip() async throws {
        let paster = ClipboardPaster()
        let testText = "YOLOWhisp integration test \(UUID().uuidString)"

        // This only tests clipboard setting, not Cmd+V (can't simulate in test)
        try await paster.output(text: testText)

        // Verify clipboard
        let clipboard = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(clipboard, testText)
    }

    // MARK: - History Persistence Integration

    func testHistorySQLitePersistence() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let dbPath = tempDir.appendingPathComponent("integration_test_\(UUID()).db").path

        defer { try? FileManager.default.removeItem(atPath: dbPath) }

        // Write
        let store1 = HistoryStore(databasePath: dbPath)
        let entry = HistoryEntry(
            rawText: "Integration test entry",
            processedText: "Polished integration test entry",
            duration: 2.5,
            modelUsed: "ggml-small",
            targetApp: "Xcode"
        )
        try store1.save(entry: entry)

        // Read from new instance
        let store2 = HistoryStore(databasePath: dbPath)
        let entries = try store2.entries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].rawText, "Integration test entry")
        XCTAssertEqual(entries[0].processedText, "Polished integration test entry")
        XCTAssertEqual(entries[0].modelUsed, "ggml-small")
        XCTAssertEqual(entries[0].targetApp, "Xcode")
    }

    // MARK: - DictationController Integration

    func testDictationControllerFullFlow() async throws {
        // Uses real history store but mocked audio/transcription
        let mockAudio = MockIntegrationAudio()
        let mockTranscriber = MockIntegrationTranscriber(
            result: TranscriptionResult(text: "Hello world.", duration: 0.5, modelUsed: "small")
        )
        let clipboard = ClipboardPaster()
        let outputManager = TextOutputManager(outputs: [.clipboardPaste: clipboard])
        let historyStore = HistoryStore() // in-memory
        let pill = MockIntegrationPill()

        let controller = DictationController(
            audioCapture: mockAudio,
            transcriber: mockTranscriber,
            textOutputManager: outputManager,
            historyStore: historyStore,
            pill: pill
        )

        controller.outputMode = .clipboardPaste
        controller.startDictation()
        XCTAssertTrue(controller.isActive)

        await controller.stopDictation()
        XCTAssertFalse(controller.isActive)

        // Verify history saved
        let entries = try historyStore.entries(limit: 10)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].rawText, "Hello world.")

        // Verify clipboard
        let clipboard_content = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(clipboard_content, "Hello world.")

        // Verify pill state transitions
        XCTAssertEqual(pill.stateHistory, [.recording, .processing, .idle])
    }
}

// MARK: - Integration Test Helpers

private final class MockIntegrationAudio: AudioCapturing {
    var isCapturing = false
    func startCapture() { isCapturing = true }
    func stopCapture() -> Data {
        isCapturing = false
        return Data(repeating: 0, count: 32000)
    }
}

private final class MockIntegrationTranscriber: Transcribing {
    let result: TranscriptionResult
    init(result: TranscriptionResult) { self.result = result }
    func transcribe(audioData: Data) async throws -> TranscriptionResult { result }
}

private final class MockIntegrationPill: PillDisplaying {
    var position: CGPoint = .zero
    var stateHistory: [PillState] = []
    func show() {}
    func hide() {}
    func setState(_ state: PillState) { stateHistory.append(state) }
}
