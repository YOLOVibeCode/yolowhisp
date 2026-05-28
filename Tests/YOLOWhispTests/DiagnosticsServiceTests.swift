import XCTest
@testable import YOLOWhisp

@MainActor
final class DiagnosticsServiceTests: XCTestCase {

    private final class StubPermissions: PermissionChecking {
        let mic: Bool; let ax: Bool
        init(mic: Bool, ax: Bool) { self.mic = mic; self.ax = ax }
        func checkMicrophonePermission() -> Bool { mic }
        func requestMicrophonePermission() async -> Bool { mic }
        func checkAccessibilityPermission() -> Bool { ax }
        func openAccessibilitySettings() {}
    }

    private func makeService(mic: Bool, ax: Bool, whisperPath: String) -> DiagnosticsService {
        let controller = DictationController(
            audioCapture: MockAudioCapture(),
            transcriber: MockTranscriber(),
            textOutputManager: TextOutputManager(outputs: [:]),
            historyStore: MockHistoryStore(),
            pill: MockPillDisplay()
        )
        let services = AppServices(
            controller: controller,
            audioCapture: AudioCaptureEngine(),
            modelManager: ModelManager(searchPaths: ["/nonexistent-\(UUID().uuidString)"]),
            hotkeyManager: HotkeyManager(),
            permissions: StubPermissions(mic: mic, ax: ax),
            whisperPath: whisperPath,
            sampleProvider: { nil },
            aiConfigProvider: { nil }
        )
        return DiagnosticsService(services: services)
    }

    func testMicPermissionMapsToStatus() async {
        let denied = await makeService(mic: false, ax: true, whisperPath: "/bin/echo").run(.micPermission).status
        XCTAssertEqual(denied, .fail)
        let granted = await makeService(mic: true, ax: true, whisperPath: "/bin/echo").run(.micPermission).status
        XCTAssertEqual(granted, .ok)
    }

    func testAccessibilityMapsToStatus() async {
        let off = await makeService(mic: true, ax: false, whisperPath: "/bin/echo").run(.accessibilityPermission).status
        XCTAssertEqual(off, .fail)
        let on = await makeService(mic: true, ax: true, whisperPath: "/bin/echo").run(.accessibilityPermission).status
        XCTAssertEqual(on, .ok)
    }

    func testWhisperCLIPresenceMapsToStatus() async {
        let missing = await makeService(mic: true, ax: true, whisperPath: "/nope/whisper-cli").run(.whisperCLI).status
        XCTAssertEqual(missing, .fail)
        let present = await makeService(mic: true, ax: true, whisperPath: "/bin/echo").run(.whisperCLI).status
        XCTAssertEqual(present, .ok)
    }

    func testModelFailsWhenNoneLoaded() async {
        let r = await makeService(mic: true, ax: true, whisperPath: "/bin/echo").run(.modelLoaded)
        XCTAssertEqual(r.status, .fail)
        XCTAssertNotNil(r.remediation)
    }

    func testEndToEndSkippedWithoutSample() async {
        let s = await makeService(mic: true, ax: true, whisperPath: "/bin/echo").run(.endToEnd).status
        XCTAssertEqual(s, .skipped)
    }

    func testAIProviderSkippedWhenDisabled() async {
        let s = await makeService(mic: true, ax: true, whisperPath: "/bin/echo").run(.aiProvider).status
        XCTAssertEqual(s, .skipped)
    }

    // "Set up everything" must run fixes in a sensible order and skip non-fixable/ok rows.
    func testFixableStagesOrderedAndFiltered() async {
        let svc = makeService(mic: true, ax: true, whisperPath: "/bin/echo")
        svc.results = [
            .modelLoaded: CheckResult(id: .modelLoaded, status: .fail, detail: "", remediation: nil, fix: .downloadModel),
            .micPermission: CheckResult(id: .micPermission, status: .fail, detail: "", remediation: nil, fix: .requestMic),
            .whisperCLI: CheckResult(id: .whisperCLI, status: .fail, detail: "", remediation: nil, fix: .installWhisper),
            .accessibilityPermission: CheckResult(id: .accessibilityPermission, status: .warn, detail: "", remediation: nil, fix: .openAccessibility),
            .inputDevice: CheckResult(id: .inputDevice, status: .ok, detail: "", remediation: nil, fix: nil),
        ]
        XCTAssertEqual(svc.fixableStages().map(\.fix),
                       [.requestMic, .openAccessibility, .installWhisper, .downloadModel])
    }
}
