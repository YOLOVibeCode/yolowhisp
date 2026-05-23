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
}
