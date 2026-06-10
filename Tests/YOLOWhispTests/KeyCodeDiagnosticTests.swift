import XCTest
@testable import YOLOWhisp

/// Diagnostic tests to verify key-code mappings match expectations.
/// These help debug issues like "punctuation becomes slash in RDP".
final class KeyCodeDiagnosticTests: XCTestCase {
    
    func testPunctuationKeyCodeMappings() {
        // Print out the actual keyCode for each punctuation character
        // to help debug RDP typing issues
        let punctuation = [".", ",", "!", "?", ";", ":", "'", "\"", "/", "\\"]
        
        print("\n=== Punctuation KeyCode Mappings ===")
        for char in punctuation {
            if let mapping = KeystrokeTyper.keyMap[Character(char)] {
                print("'\(char)' -> keyCode: \(mapping.keyCode), shift: \(mapping.shift)")
            } else {
                print("'\(char)' -> NO MAPPING")
            }
        }
        print("=====================================\n")
    }
    
    func testForwardSlashVsPeriod() {
        // Specific test for the slash/period confusion the user reported
        guard let slashMap = KeystrokeTyper.keyMap["/"],
              let periodMap = KeystrokeTyper.keyMap["."],
              let questionMap = KeystrokeTyper.keyMap["?"] else {
            XCTFail("Missing mappings for slash/period/question")
            return
        }
        
        print("\n=== Slash vs Period Diagnostic ===")
        print("'/' (slash)    -> keyCode: \(slashMap.keyCode), shift: \(slashMap.shift)")
        print("'.' (period)   -> keyCode: \(periodMap.keyCode), shift: \(periodMap.shift)")
        print("'?' (question) -> keyCode: \(questionMap.keyCode), shift: \(questionMap.shift)")
        print("===================================\n")
        
        // On US QWERTY:
        // '/' is key 44, no shift
        // '?' is key 44, WITH shift (same key as /)
        // '.' is key 47, no shift
        XCTAssertNotEqual(slashMap.keyCode, periodMap.keyCode, "Slash and period should use different keys")
        XCTAssertEqual(slashMap.keyCode, questionMap.keyCode, "Slash and question should share a key")
    }
    
    func testAllPrintableASCIIHaveMappings() {
        // Verify every printable ASCII character has a keyCode mapping
        var missing: [Character] = []
        
        for ascii in 32...126 {
            let char = Character(UnicodeScalar(ascii)!)
            if KeystrokeTyper.keyMap[char] == nil {
                missing.append(char)
            }
        }
        
        if !missing.isEmpty {
            XCTFail("Missing keyCode mappings for: \(missing.map { "'\($0)'" }.joined(separator: ", "))")
        }
    }
    
    func testKeyCodeUniqueness() {
        // Verify that shifted/unshifted pairs are the only duplicates
        var keyCodes: [CGKeyCode: [(char: Character, shift: Bool)]] = [:]
        
        for (char, mapping) in KeystrokeTyper.keyMap {
            keyCodes[mapping.keyCode, default: []].append((char, mapping.shift))
        }
        
        print("\n=== KeyCode Sharing (should only be shift pairs) ===")
        for (keyCode, chars) in keyCodes.sorted(by: { $0.key < $1.key }) where chars.count > 1 {
            let charList = chars.map { "'\($0.char)' (shift:\($0.shift))" }.joined(separator: ", ")
            print("KeyCode \(keyCode): \(charList)")
            
            // Verify it's a valid shift pair (one shifted, one not)
            let shiftCount = chars.filter(\.shift).count
            let unshiftedCount = chars.filter { !$0.shift }.count
            XCTAssertEqual(chars.count, 2, "KeyCode \(keyCode) has \(chars.count) mappings (expected 2)")
            XCTAssertEqual(shiftCount, 1, "KeyCode \(keyCode) should have exactly 1 shifted char")
            XCTAssertEqual(unshiftedCount, 1, "KeyCode \(keyCode) should have exactly 1 unshifted char")
        }
        print("====================================================\n")
    }
}
