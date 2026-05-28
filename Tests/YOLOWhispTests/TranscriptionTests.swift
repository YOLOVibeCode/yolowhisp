import XCTest
@testable import YOLOWhisp

final class MockProcessRunner: ProcessRunning {
    var lastExecutablePath: String?
    var lastArguments: [String]?
    var lastEnvironment: [String: String]?
    var stubbedResult: (stdout: String, stderr: String, exitCode: Int32) = ("", "", 0)
    var shouldThrow: Error?

    func run(executablePath: String, arguments: [String], environment: [String: String]?) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        lastExecutablePath = executablePath
        lastArguments = arguments
        lastEnvironment = environment
        if let error = shouldThrow { throw error }
        return stubbedResult
    }
}

final class MockModelManager: ModelManaging {
    var currentModel: WhisperModel?
    var models: [WhisperModel] = []

    func availableModels() -> [WhisperModel] { models }
    func loadModel(_ model: WhisperModel) throws { currentModel = model }
}

final class TranscriptionTests: XCTestCase {
    func testConformsToProtocol() {
        let mm = MockModelManager()
        let engine: any Transcribing = WhisperEngine(modelManager: mm)
        XCTAssertNotNil(engine)
    }

    func testParseWhisperOutput() {
        let output = """
        [00:00:00.000 --> 00:00:03.000]   Hello world
        [00:00:03.000 --> 00:00:06.000]   This is a test

        """
        let result = WhisperEngine.parseOutput(output)
        XCTAssertEqual(result, "Hello world This is a test")
    }

    func testParseWhisperOutputEmpty() {
        XCTAssertEqual(WhisperEngine.parseOutput(""), "")
    }

    func testTranscribeEmptyAudioThrows() async {
        let mm = MockModelManager()
        mm.currentModel = WhisperModel(name: "small", path: "/tmp/small.bin", size: 100)
        let engine = WhisperEngine(modelManager: mm, processRunner: MockProcessRunner())

        do {
            _ = try await engine.transcribe(audioData: Data())
            XCTFail("Expected emptyAudio error")
        } catch {
            XCTAssertEqual(error as? WhisperError, .emptyAudio)
        }
    }

    func testTranscribeNoModelLoadedThrows() async {
        let mm = MockModelManager()
        let engine = WhisperEngine(modelManager: mm, processRunner: MockProcessRunner())

        do {
            _ = try await engine.transcribe(audioData: Data([0x01, 0x02]))
            XCTFail("Expected noModelLoaded error")
        } catch {
            XCTAssertEqual(error as? WhisperError, .noModelLoaded)
        }
    }

    func testTranscribeCallsProcessWithCorrectArgs() async throws {
        let mm = MockModelManager()
        mm.currentModel = WhisperModel(name: "base", path: "/models/ggml-base.bin", size: 100)
        let runner = MockProcessRunner()
        runner.stubbedResult = (stdout: "[00:00:00.000 --> 00:00:01.000]   Hi\n", stderr: "", exitCode: 0)
        let engine = WhisperEngine(whisperPath: "/usr/bin/whisper-cli", modelManager: mm, processRunner: runner)

        let result = try await engine.transcribe(audioData: Data([0x01, 0x02]))

        XCTAssertEqual(runner.lastExecutablePath, "/usr/bin/whisper-cli")
        XCTAssertEqual(runner.lastArguments?[0], "-m")
        XCTAssertEqual(runner.lastArguments?[1], "/models/ggml-base.bin")
        XCTAssertEqual(runner.lastArguments?[2], "-f")
        // lastArguments[3] is the temp wav path
        XCTAssertEqual(runner.lastArguments?[4], "-l")
        XCTAssertEqual(runner.lastArguments?[5], "en")
        XCTAssertEqual(runner.lastArguments?[6], "-np")
        XCTAssertEqual(result.text, "Hi")
        XCTAssertEqual(result.modelUsed, "base")
    }

    func testTempFileCleanedUp() async throws {
        let mm = MockModelManager()
        mm.currentModel = WhisperModel(name: "base", path: "/models/ggml-base.bin", size: 100)
        let runner = MockProcessRunner()
        runner.stubbedResult = (stdout: "[00:00:00.000 --> 00:00:01.000]   test\n", stderr: "", exitCode: 0)
        let engine = WhisperEngine(modelManager: mm, processRunner: runner)

        _ = try await engine.transcribe(audioData: Data([0x01, 0x02]))

        // The temp wav path was passed as argument[3]
        if let wavPath = runner.lastArguments?[3] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: wavPath), "Temp WAV file should be cleaned up")
        } else {
            XCTFail("Expected wav path in arguments")
        }
    }
}
