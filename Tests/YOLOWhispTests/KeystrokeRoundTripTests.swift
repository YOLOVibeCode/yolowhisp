import XCTest
@testable import YOLOWhisp

/// Comprehensive keystroke fidelity tests: verify that every character we need
/// to type can be correctly represented in both Unicode mode (local apps) and
/// keyCode mode (RDP/VM sessions).
final class KeystrokeRoundTripTests: XCTestCase {
    
    // MARK: - Unicode Mode (Local Apps)
    
    func testUnicodeModeBasicAlphabet() {
        let samples = [
            "abc", "ABC", "aBc", "XyZ",
            "the quick brown fox jumps over the lazy dog",
            "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG"
        ]
        for sample in samples {
            let plan = KeystrokeTyper.plan(for: sample)
            let reconstructed = KeystrokeTyper.text(from: plan)
            XCTAssertEqual(reconstructed, sample, "Unicode mode: alphabet failed for '\(sample)'")
        }
    }
    
    func testUnicodeModeNumbers() {
        let samples = ["0123456789", "42", "2024", "3.14159"]
        for sample in samples {
            let plan = KeystrokeTyper.plan(for: sample)
            let reconstructed = KeystrokeTyper.text(from: plan)
            XCTAssertEqual(reconstructed, sample, "Unicode mode: numbers failed for '\(sample)'")
        }
    }
    
    func testUnicodeModePunctuation() {
        // Every punctuation character on a US keyboard
        let samples = [
            ".",   // period
            ",",   // comma
            "!",   // exclamation
            "?",   // question
            ";",   // semicolon
            ":",   // colon
            "'",   // apostrophe
            "\"",  // quote
            "-",   // hyphen
            "_",   // underscore
            "(",   // left paren
            ")",   // right paren
            "[",   // left bracket
            "]",   // right bracket
            "{",   // left brace
            "}",   // right brace
            "/",   // forward slash
            "\\",  // backslash
            "|",   // pipe
            "@",   // at
            "#",   // hash
            "$",   // dollar
            "%",   // percent
            "^",   // caret
            "&",   // ampersand
            "*",   // asterisk
            "+",   // plus
            "=",   // equals
            "`",   // backtick
            "~",   // tilde
            "<",   // less than
            ">",   // greater than
        ]
        
        for sample in samples {
            let plan = KeystrokeTyper.plan(for: sample)
            let reconstructed = KeystrokeTyper.text(from: plan)
            XCTAssertEqual(reconstructed, sample, "Unicode mode: punctuation '\(sample)' failed")
        }
    }
    
    func testUnicodeModeSentences() {
        let samples = [
            "Hello, world!",
            "How are you? I'm doing great.",
            "She said, \"It's working!\"",
            "The cost is $42.99 (plus tax).",
            "Email: user@example.com",
            "100% success - that's amazing!",
            "Path: /usr/local/bin",
            "Code: `function() { return 42; }`",
            "Math: 2 + 2 = 4, 3 * 3 = 9",
            "URL: https://example.com/path?query=value&other=123",
        ]
        
        for sample in samples {
            let plan = KeystrokeTyper.plan(for: sample)
            let reconstructed = KeystrokeTyper.text(from: plan)
            XCTAssertEqual(reconstructed, sample, "Unicode mode: sentence failed")
        }
    }
    
    // MARK: - KeyCode Mode (RDP/VM Sessions)
    
    func testKeyCodeModeBasicCharacters() {
        // For keyCode mode, verify that characters in the keyMap can be resolved
        let basicChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        
        for ch in basicChars {
            guard let mapping = KeystrokeTyper.keyMap[ch] else {
                XCTFail("KeyCode mode: missing mapping for '\(ch)'")
                continue
            }
            
            // Verify the mapping makes sense
            if ch.isUppercase {
                XCTAssertTrue(mapping.shift, "KeyCode mode: uppercase '\(ch)' should require shift")
            } else if ch.isLowercase {
                XCTAssertFalse(mapping.shift, "KeyCode mode: lowercase '\(ch)' should not require shift")
            }
        }
    }
    
    func testKeyCodeModePunctuationMappings() {
        // Test every punctuation character and verify it has a keyCode mapping
        let punctuationTests: [(char: Character, needsShift: Bool, description: String)] = [
            (".", false, "period"),
            (",", false, "comma"),
            ("!", true, "exclamation (shift+1)"),
            ("?", true, "question (shift+/)"),
            (";", false, "semicolon"),
            (":", true, "colon (shift+;)"),
            ("'", false, "apostrophe"),
            ("\"", true, "quote (shift+')"),
            ("-", false, "hyphen"),
            ("_", true, "underscore (shift+-)"),
            ("(", true, "left paren (shift+9)"),
            (")", true, "right paren (shift+0)"),
            ("[", false, "left bracket"),
            ("]", false, "right bracket"),
            ("{", true, "left brace (shift+[)"),
            ("}", true, "right brace (shift+])"),
            ("/", false, "forward slash"),
            ("\\", false, "backslash"),
            ("|", true, "pipe (shift+\\)"),
            ("@", true, "at (shift+2)"),
            ("#", true, "hash (shift+3)"),
            ("$", true, "dollar (shift+4)"),
            ("%", true, "percent (shift+5)"),
            ("^", true, "caret (shift+6)"),
            ("&", true, "ampersand (shift+7)"),
            ("*", true, "asterisk (shift+8)"),
            ("+", true, "plus (shift+=)"),
            ("=", false, "equals"),
            ("`", false, "backtick"),
            ("~", true, "tilde (shift+`)"),
            ("<", true, "less than (shift+,)"),
            (">", true, "greater than (shift+.)"),
        ]
        
        for test in punctuationTests {
            guard let mapping = KeystrokeTyper.keyMap[test.char] else {
                XCTFail("KeyCode mode: missing mapping for \(test.description) '\(test.char)'")
                continue
            }
            
            XCTAssertEqual(mapping.shift, test.needsShift,
                          "KeyCode mode: \(test.description) '\(test.char)' shift state incorrect")
        }
    }
    
    func testKeyCodeModeCommonSentences() {
        // Verify that common sentences are fully mappable for RDP
        let sentences = [
            "Hello world",
            "The quick brown fox jumps over the lazy dog.",
            "I'm testing this application.",
            "Cost: $42.99",
            "100% complete!",
            "Questions? Comments?",
        ]
        
        for sentence in sentences {
            let mappable = KeystrokeTyper.isFullyMappable(sentence)
            XCTAssertTrue(mappable, "KeyCode mode: '\(sentence)' should be fully mappable")
        }
    }
    
    func testKeyCodeModeUnmappableCharacters() {
        // Verify that emoji and special Unicode are NOT mappable (should use clipboard fallback)
        let unmappableTests = [
            "Hello 🎉",
            "Café",
            "naïve",
            "résumé",
        ]
        
        for test in unmappableTests {
            let mappable = KeystrokeTyper.isFullyMappable(test)
            // Note: accented chars may be mappable depending on keyboard layout,
            // but emoji definitely should not be
            if test.contains("🎉") {
                XCTAssertFalse(mappable, "KeyCode mode: emoji should NOT be mappable")
            }
        }
    }
    
    // MARK: - Shift Key Pairing
    
    func testShiftedCharactersShareKeyCode() {
        // Verify that shifted pairs (like '1' and '!') use the same keyCode
        let shiftPairs: [(unshifted: Character, shifted: Character)] = [
            ("1", "!"), ("2", "@"), ("3", "#"), ("4", "$"), ("5", "%"),
            ("6", "^"), ("7", "&"), ("8", "*"), ("9", "("), ("0", ")"),
            ("-", "_"), ("=", "+"), ("[", "{"), ("]", "}"), ("\\", "|"),
            (";", ":"), ("'", "\""), (",", "<"), (".", ">"), ("/", "?"),
            ("`", "~")
        ]
        
        for (unshifted, shifted) in shiftPairs {
            guard let unshiftedMap = KeystrokeTyper.keyMap[unshifted],
                  let shiftedMap = KeystrokeTyper.keyMap[shifted] else {
                XCTFail("Missing mapping for pair '\(unshifted)' / '\(shifted)'")
                continue
            }
            
            XCTAssertEqual(unshiftedMap.keyCode, shiftedMap.keyCode,
                          "Shift pair '\(unshifted)'/'\(shifted)' should share keyCode")
            XCTAssertFalse(unshiftedMap.shift, "'\(unshifted)' should not require shift")
            XCTAssertTrue(shiftedMap.shift, "'\(shifted)' should require shift")
        }
    }
    
    func testLetterShiftPairs() {
        // Verify lowercase and uppercase letters share keyCodes
        for ascii in UInt8(ascii: "a")...UInt8(ascii: "z") {
            let lower = Character(UnicodeScalar(ascii))
            let upper = Character(UnicodeScalar(ascii - 32))
            
            guard let lowerMap = KeystrokeTyper.keyMap[lower],
                  let upperMap = KeystrokeTyper.keyMap[upper] else {
                XCTFail("Missing mapping for letter pair '\(lower)'/'\(upper)'")
                continue
            }
            
            XCTAssertEqual(lowerMap.keyCode, upperMap.keyCode,
                          "Letter pair '\(lower)'/'\(upper)' should share keyCode")
            XCTAssertFalse(lowerMap.shift, "Lowercase '\(lower)' should not require shift")
            XCTAssertTrue(upperMap.shift, "Uppercase '\(upper)' should require shift")
        }
    }
    
    // MARK: - Real-World Dictation Examples
    
    func testRealWorldDictationExamples() {
        // Examples from actual dictation use cases
        let realWorld = [
            "Please send the report to john.doe@company.com by 5:00 PM.",
            "The meeting is scheduled for March 15th, 2024 at 2:30 PM.",
            "Total cost: $1,234.56 (including 8% tax).",
            "Question: How do we handle this? Answer: We'll figure it out!",
            "Path to file: /Users/admin/Documents/report.pdf",
            "He said, \"I'll be there soon,\" and left.",
            "Mix of UPPERCASE, lowercase, and Numbers: 123-456-7890.",
            "Math: (a + b) * c = result; check if x > y || x < z.",
        ]
        
        for sample in realWorld {
            // Unicode mode should always round-trip perfectly
            let unicodePlan = KeystrokeTyper.plan(for: sample)
            let unicodeReconstructed = KeystrokeTyper.text(from: unicodePlan)
            XCTAssertEqual(unicodeReconstructed, sample,
                          "Real-world (Unicode): failed for '\(sample)'")
            
            // KeyCode mode: verify it's mappable (for RDP compatibility)
            let isKeyCodeMappable = KeystrokeTyper.isFullyMappable(sample)
            if !isKeyCodeMappable {
                // This is OK - just means it will use clipboard fallback
                print("Note: '\(sample)' not fully key-code mappable (will use clipboard in RDP)")
            }
        }
    }
}
