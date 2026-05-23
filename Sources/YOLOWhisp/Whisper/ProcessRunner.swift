import Foundation

public protocol ProcessRunning {
    func run(executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32)
}

public final class ProcessRunner: ProcessRunning {
    public init() {}

    public func run(executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32) {
        guard FileManager.default.fileExists(atPath: executablePath) else {
            throw WhisperError.whisperNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return (stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
