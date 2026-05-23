import Foundation

public enum WhisperError: Error, Equatable {
    case noModelLoaded
    case emptyAudio
    case processError(String)
    case whisperNotFound
}

public final class WhisperEngine: Transcribing {
    private let whisperPath: String
    private let modelManager: ModelManaging
    private let processRunner: ProcessRunning

    public init(
        whisperPath: String = "/opt/homebrew/bin/whisper-cli",
        modelManager: ModelManaging,
        processRunner: ProcessRunning = ProcessRunner()
    ) {
        self.whisperPath = whisperPath
        self.modelManager = modelManager
        self.processRunner = processRunner
    }

    public func transcribe(audioData: Data) async throws -> TranscriptionResult {
        guard !audioData.isEmpty else {
            throw WhisperError.emptyAudio
        }

        guard let model = modelManager.currentModel else {
            throw WhisperError.noModelLoaded
        }

        let tempDir = FileManager.default.temporaryDirectory
        let wavPath = tempDir.appendingPathComponent(UUID().uuidString + ".wav").path
        let wavData = AudioCaptureEngine.createWAVData(from: audioData)

        FileManager.default.createFile(atPath: wavPath, contents: wavData)
        defer {
            try? FileManager.default.removeItem(atPath: wavPath)
        }

        let start = Date()
        let result = try processRunner.run(
            executablePath: whisperPath,
            arguments: ["-m", model.path, "-f", wavPath, "-l", "en", "-np"]
        )

        guard result.exitCode == 0 else {
            throw WhisperError.processError(result.stderr)
        }

        let text = Self.parseOutput(result.stdout)
        let duration = Date().timeIntervalSince(start)

        return TranscriptionResult(text: text, duration: duration, modelUsed: model.name)
    }

    static func parseOutput(_ stdout: String) -> String {
        // whisper-cli outputs lines like: [00:00:00.000 --> 00:00:05.000]   Hello world
        let lines = stdout.components(separatedBy: "\n")
        var texts: [String] = []
        for line in lines {
            if let range = line.range(of: "]") {
                let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    texts.append(text)
                }
            }
        }
        return texts.joined(separator: " ")
    }
}
