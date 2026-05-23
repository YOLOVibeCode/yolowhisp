import XCTest
@testable import YOLOWhisp

final class HotkeyTests: XCTestCase {
    func testManagerConformsToProtocol() {
        let manager: any HotkeyListening = HotkeyManager()
        XCTAssertNotNil(manager)
    }

    func testRecorderConformsToProtocol() {
        let recorder: any HotkeyRecording = HotkeyRecorderController()
        XCTAssertNotNil(recorder)
    }

    // MARK: - HotkeyConfig Hashable

    func testHotkeyConfigIsHashable() {
        let a = HotkeyConfig(keyCode: 49, modifiers: 256)
        let b = HotkeyConfig(keyCode: 49, modifiers: 256)
        let c = HotkeyConfig(keyCode: 50, modifiers: 512)
        XCTAssertEqual(a.hashValue, b.hashValue)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)

        var set = Set<HotkeyConfig>()
        set.insert(a)
        set.insert(b)
        XCTAssertEqual(set.count, 1)
        set.insert(c)
        XCTAssertEqual(set.count, 2)
    }

    // MARK: - HotkeyConfig Codable

    func testHotkeyConfigIsCodable() throws {
        let original = HotkeyConfig(keyCode: 36, modifiers: 1048840,
                                    triggerMode: .toggle, outputMode: .clipboardPaste,
                                    postProcessEnabled: true, modelOverride: "large-v3")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotkeyConfig.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - HotkeyManager register/unregister

    func testRegisterStoresHandler() {
        let manager = HotkeyManager()
        let config = HotkeyConfig(keyCode: 0, modifiers: 0)
        XCTAssertEqual(manager.registeredCount, 0)
        manager.register(hotkey: config) {}
        XCTAssertEqual(manager.registeredCount, 1)
    }

    func testUnregisterRemovesHandler() {
        let manager = HotkeyManager()
        let config = HotkeyConfig(keyCode: 0, modifiers: 0)
        manager.register(hotkey: config) {}
        XCTAssertEqual(manager.registeredCount, 1)
        manager.unregister(hotkey: config)
        XCTAssertEqual(manager.registeredCount, 0)
    }

    func testUnregisterAllClearsAll() {
        let manager = HotkeyManager()
        manager.register(hotkey: HotkeyConfig(keyCode: 0, modifiers: 0)) {}
        manager.register(hotkey: HotkeyConfig(keyCode: 1, modifiers: 0)) {}
        manager.register(hotkey: HotkeyConfig(keyCode: 2, modifiers: 256)) {}
        XCTAssertEqual(manager.registeredCount, 3)
        manager.unregisterAll()
        XCTAssertEqual(manager.registeredCount, 0)
    }

    // MARK: - DoubleTapDetector

    func testDoubleTapWithinThreshold() {
        let detector = DoubleTapDetector(threshold: 1.0)
        XCTAssertFalse(detector.tap()) // first tap
        XCTAssertTrue(detector.tap())  // second tap immediately
    }

    func testDoubleTapBeyondThreshold() {
        let detector = DoubleTapDetector(threshold: 0.01)
        XCTAssertFalse(detector.tap())
        Thread.sleep(forTimeInterval: 0.02)
        XCTAssertFalse(detector.tap())
    }

    func testDoubleTapReset() {
        let detector = DoubleTapDetector(threshold: 1.0)
        _ = detector.tap()
        detector.reset()
        // After reset, next tap should be treated as first tap
        XCTAssertFalse(detector.tap())
    }

    // MARK: - HotkeyRecorderController

    // MARK: - Hold mode (keyDown + keyUp)

    func testRegisterWithKeyUpHandler() {
        let manager = HotkeyManager()
        let config = HotkeyConfig(keyCode: 49, modifiers: 0, triggerMode: .hold)
        XCTAssertEqual(manager.registeredCount, 0)
        manager.register(hotkey: config, onKeyDown: {}, onKeyUp: {})
        XCTAssertEqual(manager.registeredCount, 1)
    }

    func testKeyUpHandlerFires() {
        // We can't simulate NSEvents in unit tests, but we can verify handler storage.
        let manager = HotkeyManager()
        var downCalled = false
        var upCalled = false
        let config = HotkeyConfig(keyCode: 49, modifiers: 0, triggerMode: .hold)
        manager.register(hotkey: config, onKeyDown: { downCalled = true }, onKeyUp: { upCalled = true })
        // Handlers are stored — registeredCount reflects keyDown handler
        XCTAssertEqual(manager.registeredCount, 1)
        // keyUpHandlerCount should also be 1
        XCTAssertEqual(manager.keyUpHandlerCount, 1)
        // Unregister should clear both
        manager.unregister(hotkey: config)
        XCTAssertEqual(manager.registeredCount, 0)
        XCTAssertEqual(manager.keyUpHandlerCount, 0)
    }

    func testHotkeyConfigFromAppStorage() {
        // Simulate building a HotkeyConfig from raw AppStorage values
        let keyCode: Int = 49
        let modifiers: Int = 0
        let triggerModeRaw: String = TriggerMode.hold.rawValue

        let config = HotkeyConfig(
            keyCode: UInt16(keyCode),
            modifiers: UInt(modifiers),
            triggerMode: TriggerMode(rawValue: triggerModeRaw) ?? .hold
        )
        XCTAssertEqual(config.keyCode, 49)
        XCTAssertEqual(config.modifiers, 0)
        XCTAssertEqual(config.triggerMode, .hold)
    }

    func testUnregisterAllClearsKeyUpHandlers() {
        let manager = HotkeyManager()
        manager.register(hotkey: HotkeyConfig(keyCode: 0, modifiers: 0, triggerMode: .hold),
                         onKeyDown: {}, onKeyUp: {})
        manager.register(hotkey: HotkeyConfig(keyCode: 1, modifiers: 0, triggerMode: .hold),
                         onKeyDown: {}, onKeyUp: {})
        XCTAssertEqual(manager.keyUpHandlerCount, 2)
        manager.unregisterAll()
        XCTAssertEqual(manager.keyUpHandlerCount, 0)
    }

    // MARK: - HotkeyRecorderController

    func testRecorderIsRecordingState() {
        let recorder = HotkeyRecorderController()
        XCTAssertFalse(recorder.isRecording)
        recorder.startRecording { _ in }
        XCTAssertTrue(recorder.isRecording)
        recorder.cancelRecording()
        XCTAssertFalse(recorder.isRecording)
    }
}
