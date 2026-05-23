import XCTest
@testable import YOLOWhisp

final class PillTests: XCTestCase {
    func testViewControllerConformsToProtocol() {
        let vc: any PillDisplaying = PillViewController()
        XCTAssertNotNil(vc)
    }

    func testDragControllerConformsToProtocol() {
        let dc: any PillDragging = PillDragController()
        XCTAssertNotNil(dc)
    }

    // MARK: - PillDragController

    func testDragUnlockNotInstant() {
        let dc = PillDragController()
        dc.beginLongPress()
        XCTAssertFalse(dc.isDragUnlocked, "Drag should not unlock instantly on beginLongPress")
    }

    func testDragUnlockAfterDelay() {
        let dc = PillDragController()
        dc.longPressDelay = 0.3
        dc.beginLongPress()

        let expectation = expectation(description: "drag unlocked after delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(dc.isDragUnlocked, "Drag should be unlocked after the delay")
    }

    func testCancelLongPressBeforeTimerPreventsUnlock() {
        let dc = PillDragController()
        dc.longPressDelay = 0.3
        dc.beginLongPress()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            dc.cancelLongPress()
        }

        let expectation = expectation(description: "wait past delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertFalse(dc.isDragUnlocked, "Drag should remain locked if cancelled before timer fires")
    }

    func testDragCallsPositionCallback() {
        let dc = PillDragController()
        var callbackPoint: CGPoint?
        dc.onPositionChanged = { point in
            callbackPoint = point
        }
        dc.drag(to: CGPoint(x: 50, y: 75))
        XCTAssertEqual(callbackPoint, CGPoint(x: 50, y: 75))
    }

    func testEndDragLocksAndCallsCallback() {
        let dc = PillDragController()
        dc.longPressDelay = 0.0
        dc.beginLongPress()

        let expectation = expectation(description: "unlock")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        var callbackPoint: CGPoint?
        dc.onDragEnded = { point in
            callbackPoint = point
        }
        dc.drag(to: CGPoint(x: 10, y: 20))
        dc.endDrag()
        XCTAssertFalse(dc.isDragUnlocked)
        XCTAssertEqual(callbackPoint, CGPoint(x: 10, y: 20))
    }

    func testDragUnlockedCallback() {
        let dc = PillDragController()
        dc.longPressDelay = 0.1
        var called = false
        dc.onDragUnlocked = { called = true }
        dc.beginLongPress()

        let expectation = expectation(description: "unlock callback")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(called)
    }

    // MARK: - PillViewController

    func testPositionPersistsToUserDefaults() {
        let defaults = UserDefaults(suiteName: "test.pill")!
        defaults.removePersistentDomain(forName: "test.pill")

        let vc = PillViewController(userDefaults: defaults)
        vc.position = CGPoint(x: 100, y: 200)

        XCTAssertEqual(defaults.double(forKey: "yolowhisp.pill.x"), 100)
        XCTAssertEqual(defaults.double(forKey: "yolowhisp.pill.y"), 200)

        defaults.removePersistentDomain(forName: "test.pill")
    }

    func testPositionRestoresFromUserDefaults() {
        let defaults = UserDefaults(suiteName: "test.pill")!
        defaults.removePersistentDomain(forName: "test.pill")

        defaults.set(150.0, forKey: "yolowhisp.pill.x")
        defaults.set(250.0, forKey: "yolowhisp.pill.y")

        let vc = PillViewController(userDefaults: defaults)
        XCTAssertEqual(vc.position, CGPoint(x: 150, y: 250))

        defaults.removePersistentDomain(forName: "test.pill")
    }

    func testSetStateUpdatesCurrentState() {
        let vc = PillViewController()
        vc.setState(.recording)
        XCTAssertEqual(vc.currentState, .recording)
    }

    func testShowHideTogglesVisibility() {
        let vc = PillViewController()
        XCTAssertFalse(vc.isVisible)
        vc.show()
        XCTAssertTrue(vc.isVisible)
        vc.hide()
        XCTAssertFalse(vc.isVisible)
    }

    // MARK: - NSPanel tests

    func testPillViewControllerCreatesPanel() {
        let vc = PillViewController()
        vc.show()
        XCTAssertNotNil(vc.panel, "show() should create an NSPanel")
    }

    func testPanelIsFloatingNonActivating() {
        let vc = PillViewController()
        vc.show()
        guard let panel = vc.panel else {
            return XCTFail("Panel should exist after show()")
        }
        XCTAssertEqual(panel.level, .floating)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testPanelIsNotOpaque() {
        let vc = PillViewController()
        vc.show()
        guard let panel = vc.panel else {
            return XCTFail("Panel should exist after show()")
        }
        XCTAssertFalse(panel.isOpaque)
    }

    func testStateChangesColor() {
        let vc = PillViewController()
        vc.setState(.recording)
        XCTAssertEqual(vc.pillColor, .systemRed)
        vc.setState(.processing)
        XCTAssertEqual(vc.pillColor, .systemBlue)
        vc.setState(.idle)
        XCTAssertEqual(vc.pillColor, .darkGray)
    }

    func testPanelPositionMatchesStoredPosition() {
        let defaults = UserDefaults(suiteName: "test.pill.panel")!
        defaults.removePersistentDomain(forName: "test.pill.panel")

        let vc = PillViewController(userDefaults: defaults)
        vc.show()
        vc.position = CGPoint(x: 300, y: 400)

        guard let panel = vc.panel else {
            return XCTFail("Panel should exist after show()")
        }
        XCTAssertEqual(panel.frame.origin.x, 300, accuracy: 1)
        XCTAssertEqual(panel.frame.origin.y, 400, accuracy: 1)

        defaults.removePersistentDomain(forName: "test.pill.panel")
    }
}
