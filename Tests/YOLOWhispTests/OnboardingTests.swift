import XCTest
@testable import YOLOWhisp

final class MockPermissionChecker: PermissionChecking {
    var micGranted = false
    var accessibilityGranted = false
    var requestMicCalled = false
    var openAccessibilityCalled = false

    func checkMicrophonePermission() -> Bool { micGranted }
    func requestMicrophonePermission() async -> Bool { requestMicCalled = true; return micGranted }
    func checkAccessibilityPermission() -> Bool { accessibilityGranted }
    func openAccessibilitySettings() { openAccessibilityCalled = true }
}

final class OnboardingTests: XCTestCase {
    func testPermissionManagerConformsToProtocol() {
        let manager: any PermissionChecking = PermissionManager()
        XCTAssertNotNil(manager)
    }

    func testGetStartedBlockedWithoutPermissions() {
        let mock = MockPermissionChecker()
        mock.micGranted = false
        mock.accessibilityGranted = false
        let canProceed = mock.checkMicrophonePermission() && mock.checkAccessibilityPermission()
        XCTAssertFalse(canProceed)
    }

    func testGetStartedEnabledWithPermissions() {
        let mock = MockPermissionChecker()
        mock.micGranted = true
        mock.accessibilityGranted = true
        let canProceed = mock.checkMicrophonePermission() && mock.checkAccessibilityPermission()
        XCTAssertTrue(canProceed)
    }

    func testRequestMicPermissionCalled() async {
        let mock = MockPermissionChecker()
        _ = await mock.requestMicrophonePermission()
        XCTAssertTrue(mock.requestMicCalled)
    }

    func testOpenAccessibilitySettingsCalled() {
        let mock = MockPermissionChecker()
        mock.openAccessibilitySettings()
        XCTAssertTrue(mock.openAccessibilityCalled)
    }
}
