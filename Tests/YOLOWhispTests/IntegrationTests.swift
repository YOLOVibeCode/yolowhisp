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

    /// Raw 16kHz mono PCM extracted from a bundled LibriSpeech sample WAV.
    /// Returns nil if the sample isn't present (it's gitignored, so absent in CI).
    private func sampleSpeechPCM() -> Data? {
        // .../Tests/YOLOWhispTests/IntegrationTests.swift -> repo root
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let wav = repoRoot.appendingPathComponent("benchmark/wav_samples/61-70970-0000.wav")
        guard FileManager.default.fileExists(atPath: wav.path),
              let data = try? Data(contentsOf: wav) else { return nil }
        return Self.pcm(fromWAV: data)
    }

    /// Strip the WAV container down to the raw PCM payload by locating the
    /// `data` subchunk (robust to header size / extra chunks).
    private static func pcm(fromWAV data: Data) -> Data? {
        guard let r = data.range(of: Data("data".utf8)) else { return nil }
        let start = r.upperBound + 4 // skip the 4-byte chunk-size field
        guard start <= data.count else { return nil }
        return data.subdata(in: start..<data.count)
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

    // MARK: - Real Speech End-to-End (headless: no GUI, no mic, no keystrokes)

    /// Drives the WHOLE pipeline on real recorded speech: a bundled WAV is fed
    /// in as the audio source, transcribed by the real whisper-cli engine, and
    /// the output is captured by an in-test sink (no actual keystrokes). Proves
    /// dictation works without launching the app or touching the session.
    func testRealSpeechEndToEndThroughController() async throws {
        try skipIfNoWhisper()
        guard let pcm = sampleSpeechPCM() else {
            throw XCTSkip("sample WAV not present (gitignored)")
        }

        let modelManager = ModelManager() // default search paths (~/.local/share/whisper, ...)
        let models = modelManager.availableModels()
        try XCTSkipIf(models.isEmpty, "no whisper models installed")
        try modelManager.loadModel(models.sorted { $0.size < $1.size }.first!) // smallest = fastest

        let engine = WhisperEngine(whisperPath: whisperPath, modelManager: modelManager)
        let audio = FileAudioCapture(pcm: pcm)
        let sink = CapturingTextOutput()
        let outputManager = TextOutputManager(outputs: [.simulatedKeystrokes: sink])
        let history = HistoryStore() // in-memory
        let pill = MockIntegrationPill()

        let controller = DictationController(
            audioCapture: audio,
            transcriber: engine,
            textOutputManager: outputManager,
            historyStore: history,
            pill: pill
        )
        controller.outputMode = .simulatedKeystrokes

        controller.startDictation()
        await controller.stopDictation()

        let typed = sink.captured.joined(separator: " ").lowercased()
        XCTAssertFalse(typed.isEmpty, "expected a non-empty transcription")
        // Distinctive words from this clip; robust across models/punctuation/case.
        XCTAssertTrue(typed.contains("commanded"), "transcript was: \(typed)")
        XCTAssertTrue(typed.contains("squire"), "transcript was: \(typed)")

        let entries = try history.entries(limit: 5)
        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].rawText.lowercased().contains("squire"))
        XCTAssertEqual(pill.stateHistory, [.recording, .processing, .idle])
    }

    /// Dual-model: two real whisper engines run in parallel and an offline
    /// consensus picks the winner, all through the real DictationController.
    func testDualModelConsensusEndToEnd() async throws {
        try skipIfNoWhisper()
        guard let pcm = sampleSpeechPCM() else { throw XCTSkip("sample WAV not present (gitignored)") }

        let manager = ModelManager()
        let models = manager.availableModels().sorted { $0.size < $1.size }
        try XCTSkipIf(models.count < 2, "need at least two whisper models for dual-model test")

        let mm1 = ModelManager(); try mm1.loadModel(models[0])
        let mm2 = ModelManager(); try mm2.loadModel(models[1])

        let sink = CapturingTextOutput()
        let controller = DictationController(
            audioCapture: FileAudioCapture(pcm: pcm),
            transcriber: WhisperEngine(whisperPath: whisperPath, modelManager: mm1),
            textOutputManager: TextOutputManager(outputs: [sink.mode: sink]),
            historyStore: HistoryStore(),
            pill: MockIntegrationPill()
        )
        controller.secondTranscriber = WhisperEngine(whisperPath: whisperPath, modelManager: mm2)
        controller.consensusStrategy = MajorityVoteConsensus()
        controller.outputMode = sink.mode

        controller.startDictation()
        await controller.stopDictation()

        let typed = sink.captured.joined(separator: " ").lowercased()
        XCTAssertFalse(typed.isEmpty, "dual-model consensus produced no text")
        XCTAssertTrue(typed.contains("squire"), "got: \(typed)")
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

/// Audio source that replays fixed PCM from a file instead of the mic.
private final class FileAudioCapture: AudioCapturing {
    var isCapturing = false
    private let pcm: Data
    init(pcm: Data) { self.pcm = pcm }
    func startCapture() { isCapturing = true }
    func stopCapture() -> Data {
        isCapturing = false
        return pcm
    }
}

/// Output sink that records what would have been typed — no real keystrokes,
/// so the test never touches the foreground app or clipboard.
private final class CapturingTextOutput: TextOutputting {
    let mode: OutputMode = .simulatedKeystrokes
    private(set) var captured: [String] = []
    func output(text: String) async throws { captured.append(text) }
}
