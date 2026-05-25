import XCTest
@testable import YOLOWhisp

final class ProcessRunnerTests: XCTestCase {

    func testRunsToCompletionAndCapturesStdout() throws {
        let runner = ProcessRunner(timeout: 5)
        let result = try runner.run(executablePath: "/bin/echo", arguments: ["hello world"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello world")
    }

    func testThrowsWhenExecutableMissing() {
        let runner = ProcessRunner(timeout: 5)
        XCTAssertThrowsError(try runner.run(executablePath: "/nope/not-a-binary", arguments: [])) { error in
            XCTAssertEqual(error as? WhisperError, .whisperNotFound)
        }
    }

    func testTimesOutOnLongRunningProcess() {
        let runner = ProcessRunner(timeout: 0.3)
        let start = Date()
        XCTAssertThrowsError(try runner.run(executablePath: "/bin/sleep", arguments: ["10"])) { error in
            XCTAssertEqual(error as? WhisperError, .timedOut)
        }
        // Should give up well before the 10s sleep would finish.
        XCTAssertLessThan(Date().timeIntervalSince(start), 3.0)
    }

    func testNonZeroExitCodeIsReported() throws {
        let runner = ProcessRunner(timeout: 5)
        // `false` exits 1 without timing out.
        let result = try runner.run(executablePath: "/usr/bin/false", arguments: [])
        XCTAssertEqual(result.exitCode, 1)
    }
}
