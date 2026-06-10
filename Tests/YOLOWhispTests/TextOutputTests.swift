import XCTest
@testable import YOLOWhisp

// MARK: - Mock

final class MockTextOutputter: TextOutputting {
    let mode: OutputMode
    private(set) var outputCalls: [String] = []

    init(mode: OutputMode) {
        self.mode = mode
    }

    func output(text: String) async throws {
        outputCalls.append(text)
    }
}

// MARK: - Tests

final class TextOutputTests: XCTestCase {

    // MARK: ClipboardPaster

    func testClipboardPasterConformsToProtocol() {
        let paster: any TextOutputting = ClipboardPaster()
        XCTAssertEqual(paster.mode, .clipboardPaste)
    }

    func testClipboardPasterSetsClipboard() async throws {
        let paster = ClipboardPaster()
        let testString = "hello from YOLOWhisp \(UUID().uuidString)"
        try await paster.output(text: testString)

        let result = NSPasteboard.general.string(forType: .string)
        XCTAssertEqual(result, testString)
    }

    // MARK: Paste fidelity (uses an isolated pasteboard, not the user's clipboard)

    /// A private, named pasteboard so these tests never disturb the real
    /// system clipboard.
    private func makeIsolatedPasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("com.yolowhisp.test.\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    func testStagePlacesExactTextIncludingUnicode() {
        let samples = [
            "Hello, how are you? I'm doing great today!",
            "She bought 12 apples, 3 oranges, and 1 banana.",
            "Multi\nline\ttext with tabs",
            "Café naïve résumé — déjà vu 🎉",
            "Quotes: \"double\" and 'single'.",
        ]
        for sample in samples {
            let pb = makeIsolatedPasteboard()
            ClipboardPaster.stage(text: sample, on: pb)
            XCTAssertEqual(pb.string(forType: .string), sample, "Clipboard must hold the exact text")
        }
    }

    func testStageReturnsSnapshotAndRestoreReproducesPriorClipboard() {
        let pb = makeIsolatedPasteboard()
        let original = "the user's previous clipboard 🧷"
        pb.setString(original, forType: .string)

        // Stage new text; the prior contents are returned for restoration.
        let saved = ClipboardPaster.stage(text: "dictated text", on: pb)
        XCTAssertEqual(pb.string(forType: .string), "dictated text")

        // Restoring puts the original clipboard back exactly.
        ClipboardPaster.restore(saved, to: pb)
        XCTAssertEqual(pb.string(forType: .string), original)
    }

    func testRestorePreservesMultipleDataTypes() {
        let pb = makeIsolatedPasteboard()
        let item = NSPasteboardItem()
        item.setString("plain text", forType: .string)
        item.setData(Data("<html>hi</html>".utf8), forType: .html)
        pb.writeObjects([item])

        let saved = ClipboardPaster.snapshot(pb)
        // Clobber the pasteboard, then restore.
        pb.clearContents()
        pb.setString("something else", forType: .string)
        ClipboardPaster.restore(saved, to: pb)

        XCTAssertEqual(pb.string(forType: .string), "plain text")
        XCTAssertEqual(pb.data(forType: .html), Data("<html>hi</html>".utf8))
    }

    // MARK: KeystrokeTyper

    func testKeystrokeTyperConformsToProtocol() {
        let typer: any TextOutputting = KeystrokeTyper()
        XCTAssertEqual(typer.mode, .simulatedKeystrokes)
    }

    func testKeystrokeTyperKeyCodeTable() {
        let table = KeystrokeTyper.keyMap
        // All printable ASCII 32-126
        for scalar in (32...126).compactMap(Unicode.Scalar.init) {
            let ch = Character(scalar)
            XCTAssertNotNil(table[ch], "Missing mapping for '\(ch)' (ascii \(scalar.value))")
        }
    }

    func testKeystrokeTyperShiftForUppercase() {
        let table = KeystrokeTyper.keyMap
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            guard let entry = table[letter] else {
                XCTFail("Missing mapping for '\(letter)'")
                continue
            }
            let lower = Character(letter.lowercased())
            guard let lowerEntry = table[lower] else {
                XCTFail("Missing mapping for '\(lower)'")
                continue
            }
            XCTAssertTrue(entry.shift, "'\(letter)' should require shift")
            XCTAssertEqual(entry.keyCode, lowerEntry.keyCode,
                           "'\(letter)' should share keycode with '\(lower)'")
        }
    }

    // MARK: Typing fidelity (the plan round-trips to the exact input)

    func testTypingPlanRoundTripsExactly() {
        // Stress every category that the old keycode+shift path used to corrupt:
        // mixed case, apostrophes, quotes, periods, commas, numbers, symbols,
        // accents, and emoji. Unicode injection must reproduce all of it.
        let samples = [
            "Hello, how are you? I'm doing great today!",
            "Don't forget: it's urgent, really urgent!",
            "She bought 12 apples, 3 oranges, and 1 banana.",
            "Our revenue grew 25% year over year, reaching $4.2 million.",
            "Café naïve résumé — déjà vu 🎉",
            "Quotes: \"double\" and 'single' and (parens).",
        ]
        for sample in samples {
            let plan = KeystrokeTyper.plan(for: sample)
            let reconstructed = KeystrokeTyper.text(from: plan)
            XCTAssertEqual(reconstructed, sample, "Typing plan must reproduce the input exactly")
        }
    }

    func testTypingPlanUsesUnicodeNotShiftedKeys() {
        // Uppercase and shifted punctuation must be emitted as their literal
        // characters, NOT as a virtual key that depends on a shift modifier.
        // (Regression guard for the "all CAPS / ' -> \" / . -> >" bug.)
        for ch in "A?\"".map({ String($0) }) {
            XCTAssertEqual(KeystrokeTyper.plan(for: ch), [.unicode(ch)])
        }
    }

    func testTypingPlanMapsReturnAndTabToRealKeys() {
        XCTAssertEqual(KeystrokeTyper.plan(for: "\n"), [.virtualKey(KeystrokeTyper.returnKeyCode)])
        XCTAssertEqual(KeystrokeTyper.plan(for: "\t"), [.virtualKey(KeystrokeTyper.tabKeyCode)])
        // And those reconstruct back to the whitespace characters.
        XCTAssertEqual(KeystrokeTyper.text(from: KeystrokeTyper.plan(for: "a\tb\nc")), "a\tb\nc")
    }

    // Regression: layoutKeyMap() uses Text Input Source APIs that assert the
    // main thread, but output() runs from the async dictation pipeline
    // (off-main). This used to SIGTRAP. Empty text exercises the layout query
    // without posting any real keystrokes.
    func testOutputFromBackgroundThreadDoesNotCrash() async throws {
        try await Task.detached {
            try await KeystrokeTyper().output(text: "")
        }.value
        // Reaching here (no trap) means the main-thread hop works.
    }

    func testKeystrokeTyperLayoutMapBuilds() {
        // Exercises the UCKeyTranslate path. On any Latin layout the alphabet
        // is reachable; if the active input source exposes no layout data
        // (rare on CI) the map is empty and we just verify it didn't crash.
        let map = KeystrokeTyper.layoutKeyMap()
        if !map.isEmpty {
            XCTAssertNotNil(map["a"], "expected 'a' on a Latin keyboard layout")
            XCTAssertNotNil(map["A"], "expected shifted 'A'")
            if let upperA = map["A"] {
                XCTAssertTrue(upperA.shift, "'A' should require shift")
            }
        }
    }

    // MARK: AccessibilityInserter

    func testAccessibilityInserterConformsToProtocol() {
        let inserter: any TextOutputting = AccessibilityInserter()
        XCTAssertEqual(inserter.mode, .accessibilityInsertion)
    }

    // MARK: TextOutputManager

    func testTextOutputManagerRoutesToCorrectMode() async throws {
        let mock1 = MockTextOutputter(mode: .clipboardPaste)
        let mock2 = MockTextOutputter(mode: .simulatedKeystrokes)
        let manager = TextOutputManager(outputs: [
            .clipboardPaste: mock1,
            .simulatedKeystrokes: mock2
        ])

        try await manager.output(text: "test", mode: .clipboardPaste)
        XCTAssertEqual(mock1.outputCalls, ["test"])
        XCTAssertTrue(mock2.outputCalls.isEmpty)
    }

    func testTextOutputManagerUnknownModeThrows() async {
        let manager = TextOutputManager(outputs: [:])
        do {
            try await manager.output(text: "test", mode: .clipboardPaste)
            XCTFail("Expected error for unregistered mode")
        } catch let error as TextOutputError {
            XCTAssertEqual(error, .noOutputterRegistered(mode: .clipboardPaste))
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
    
    // MARK: RemoteSessionDetector
    
    func testRemoteSessionDetectorIdentifiesRDPClients() {
        // Known RDP/VM bundle IDs should be detected as remote
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: "com.microsoft.rdc.macos", name: nil))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: "com.parallels.desktop.console", name: nil))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: "com.vmware.fusion", name: nil))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: "com.citrix.receiver.icaviewer.mac", name: nil))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: "com.p5sys.jump.mac.viewer", name: nil))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: "com.teamviewer.TeamViewer", name: nil))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: "com.realvnc.vncviewer", name: nil))
    }
    
    func testRemoteSessionDetectorIdentifiesByNameFallback() {
        // Name substring matching as fallback
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: nil, name: "Microsoft Remote Desktop"))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: nil, name: "Windows App"))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: nil, name: "Parallels Desktop"))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: nil, name: "VMware Fusion"))
        XCTAssertTrue(RemoteSessionDetector.isRemote(bundleId: nil, name: "Jump Desktop"))
    }
    
    func testRemoteSessionDetectorExcludesLocalApps() {
        // Native macOS apps should NOT be detected as remote
        XCTAssertFalse(RemoteSessionDetector.isRemote(bundleId: "com.apple.Safari", name: "Safari"))
        XCTAssertFalse(RemoteSessionDetector.isRemote(bundleId: "com.apple.TextEdit", name: "TextEdit"))
        XCTAssertFalse(RemoteSessionDetector.isRemote(bundleId: "com.microsoft.VSCode", name: "Visual Studio Code"))
        XCTAssertFalse(RemoteSessionDetector.isRemote(bundleId: "com.apple.Notes", name: "Notes"))
        XCTAssertFalse(RemoteSessionDetector.isRemote(bundleId: nil, name: "Terminal"))
    }
    
    // MARK: KeystrokeTyper - Key-code emission mode
    
    func testIsFullyMappableReturnsTrueForASCII() {
        let samples = [
            "Hello world",
            "She bought 12 apples, 3 oranges, and 1 banana.",
            "Mixed CASE with punctuation: \"quotes\" and 'apostrophes'.",
            "Tab\tand\nnewline characters",
        ]
        for sample in samples {
            XCTAssertTrue(KeystrokeTyper.isFullyMappable(sample),
                         "ASCII text '\(sample)' should be fully mappable")
        }
    }
    
    func testIsFullyMappableReturnsFalseForEmoji() {
        let samples = [
            "Hello 🎉",
            "Café naïve",  // Accented characters may not be in keyMap depending on layout
        ]
        for sample in samples {
            let mappable = KeystrokeTyper.isFullyMappable(sample)
            // Emoji definitely not mappable; accents depend on the active layout.
            // Just verify we can call the function without crashing.
            _ = mappable
        }
        // Definite case: emoji is not on any standard keyboard
        XCTAssertFalse(KeystrokeTyper.isFullyMappable("🎉"))
    }
    
    func testKeyCodeEmissionModeProducesShiftSequence() {
        // In key-code mode, a shifted character (e.g., 'A') should resolve to
        // (keyCode, needsShift=true). We can't easily verify the full event
        // sequence without posting to the system (side effects), but we can
        // verify the emission mode is set and that uppercase letters have
        // shift=true in the keyMap.
        let typer = KeystrokeTyper(emission: .keyCode)
        XCTAssertEqual(typer.emission, .keyCode)
        
        // Verify the keyMap has shift info for uppercase
        let mapping = KeystrokeTyper.keyMap["A"]
        XCTAssertNotNil(mapping)
        XCTAssertTrue(mapping!.shift, "'A' should require shift in keyCode emission")
    }
    
    // MARK: ClipboardPaster - Ctrl+V modifier
    
    func testClipboardPasterUsesConfiguredModifier() {
        let cmdVPaster = ClipboardPaster(pasteModifier: .maskCommand)
        XCTAssertEqual(cmdVPaster.pasteModifier, .maskCommand)
        
        let ctrlVPaster = ClipboardPaster(pasteModifier: .maskControl)
        XCTAssertEqual(ctrlVPaster.pasteModifier, .maskControl)
    }
    
    // Regression: isFullyMappable used to call DispatchQueue.main.sync to build
    // the layout map, which DEADLOCKED when invoked from the main thread (the
    // dictation pipeline / tests) and risked deadlocking Swift's cooperative
    // pool. It must now read a cached snapshot and return on ANY thread without
    // blocking. This test would hang (then fail) under the old implementation.
    func testIsFullyMappableDoesNotDeadlockOnMainThread() {
        // Called directly on the main test thread — must return immediately.
        XCTAssertTrue(KeystrokeTyper.isFullyMappable("Hello, world!"))
        XCTAssertFalse(KeystrokeTyper.isFullyMappable("emoji 🎉"))
    }

    func testIsFullyMappableSafeFromBackgroundThread() async {
        // And from off-main (Task.detached) — no main-thread hop, no trap.
        let result = await Task.detached {
            KeystrokeTyper.isFullyMappable("The quick brown fox.")
        }.value
        XCTAssertTrue(result)
    }

    func testRemoteClipboardPasterHasLongerDelay() {
        // Remote clipboard paster (Ctrl+V for Windows) should have a longer
        // restore delay to account for clipboard redirection lag.
        let localPaster = ClipboardPaster()
        let remotePaster = ClipboardPaster(restoreDelay: 0.6, pasteModifier: .maskControl)
        
        XCTAssertEqual(localPaster.restoreDelay, 0.4)  // default
        XCTAssertEqual(remotePaster.restoreDelay, 0.6)  // longer for remote
    }
}
