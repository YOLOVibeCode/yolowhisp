import Foundation

public protocol ProcessRunning {
    func run(executablePath: String, arguments: [String]) throws -> (stdout: String, stderr: String, exitCode: Int32)
}

public final class ProcessRunner: ProcessRunning {
    /// Maximum wall-clock time a child process may run before it is terminated.
    /// A hung `whisper-cli` would otherwise block the dictation pipeline forever.
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 120) {
        self.timeout = timeout
    }

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

        // Drain pipes concurrently so a child that writes more than the pipe
        // buffer (~64KB) can't deadlock against our post-exit read.
        var stdoutData = Data()
        var stderrData = Data()
        let drainGroup = DispatchGroup()
        let drainQueue = DispatchQueue(label: "ProcessRunner.drain", attributes: .concurrent)
        drainQueue.async(group: drainGroup) {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }
        drainQueue.async(group: drainGroup) {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        }

        try process.run()

        // Arm a watchdog that kills the process if it overruns the timeout.
        let timedOutLock = NSLock()
        var timedOut = false
        let watchdog = DispatchWorkItem {
            if process.isRunning {
                timedOutLock.lock()
                timedOut = true
                timedOutLock.unlock()
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)

        process.waitUntilExit()
        watchdog.cancel()
        drainGroup.wait()

        timedOutLock.lock()
        let didTimeOut = timedOut
        timedOutLock.unlock()
        if didTimeOut {
            throw WhisperError.timedOut
        }

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return (stdout: stdout, stderr: stderr, exitCode: process.terminationStatus)
    }
}
