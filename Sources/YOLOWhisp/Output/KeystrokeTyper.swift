import Foundation
import Carbon.HIToolbox
import AppKit

public final class KeystrokeTyper: TextOutputting {
    public let mode: OutputMode = .simulatedKeystrokes
    public init() {}

    public struct KeyMapping {
        public let keyCode: CGKeyCode
        public let shift: Bool
    }

    // US QWERTY key map for all printable ASCII (32-126)
    public static let keyMap: [Character: KeyMapping] = {
        var map = [Character: KeyMapping]()

        // a-z
        let letters: [(Character, CGKeyCode)] = [
            ("a", 0), ("b", 11), ("c", 8), ("d", 2), ("e", 14), ("f", 3),
            ("g", 5), ("h", 4), ("i", 34), ("j", 38), ("k", 40), ("l", 37),
            ("m", 46), ("n", 45), ("o", 31), ("p", 35), ("q", 12), ("r", 15),
            ("s", 1), ("t", 17), ("u", 32), ("v", 9), ("w", 13), ("x", 7),
            ("y", 16), ("z", 6)
        ]
        for (ch, code) in letters {
            map[ch] = KeyMapping(keyCode: code, shift: false)
            map[Character(ch.uppercased())] = KeyMapping(keyCode: code, shift: true)
        }

        // 0-9 and their shifted symbols
        let digits: [(Character, Character, CGKeyCode)] = [
            ("0", ")", 29), ("1", "!", 18), ("2", "@", 19), ("3", "#", 20),
            ("4", "$", 21), ("5", "%", 23), ("6", "^", 22), ("7", "&", 26),
            ("8", "*", 28), ("9", "(", 25)
        ]
        for (digit, shifted, code) in digits {
            map[digit] = KeyMapping(keyCode: code, shift: false)
            map[shifted] = KeyMapping(keyCode: code, shift: true)
        }

        // Punctuation (unshifted, shifted) keycodes
        let punctuation: [(Character, Character?, CGKeyCode)] = [
            ("-", "_", 27), ("=", "+", 24), ("[", "{", 33), ("]", "}", 30),
            ("\\", "|", 42), (";", ":", 41), ("'", "\"", 39), (",", "<", 43),
            (".", ">", 47), ("/", "?", 44), ("`", "~", 50)
        ]
        for (unshifted, shifted, code) in punctuation {
            map[unshifted] = KeyMapping(keyCode: code, shift: false)
            if let s = shifted {
                map[s] = KeyMapping(keyCode: code, shift: true)
            }
        }

        // Space, tab, newline
        map[" "] = KeyMapping(keyCode: 49, shift: false)
        map["\t"] = KeyMapping(keyCode: 48, shift: false)
        map["\n"] = KeyMapping(keyCode: 36, shift: false)

        return map
    }()

    /// Build a character→key map for the *current* keyboard layout so typing
    /// works on AZERTY / QWERTZ / Dvorak / etc., not just US QWERTY. Only
    /// characters reachable with no modifier or Shift are included; anything
    /// else (e.g. AltGr symbols) is omitted and falls back to the static US
    /// map, then clipboard.
    public static func layoutKeyMap() -> [Character: KeyMapping] {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return [:]
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        var map: [Character: KeyMapping] = [:]

        layoutData.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            guard let layout = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            let kbdType = UInt32(LMGetKbdType())
            for keyCode in UInt16(0)..<128 {
                for shift in [false, true] {
                    let modifierState: UInt32 = shift ? 2 : 0  // (shiftKey >> 8) & 0xFF
                    var deadKeyState: UInt32 = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    var length = 0
                    let status = UCKeyTranslate(
                        layout, keyCode, UInt16(kUCKeyActionDown), modifierState, kbdType,
                        UInt32(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                        chars.count, &length, &chars
                    )
                    guard status == noErr, length == 1,
                          let scalar = UnicodeScalar(UInt32(chars[0])),
                          scalar.value >= 0x20, scalar.value != 0x7F else { continue }
                    let ch = Character(scalar)
                    // First write wins; shift=false is tried first so the
                    // unshifted key is preferred for a given character.
                    if map[ch] == nil {
                        map[ch] = KeyMapping(keyCode: CGKeyCode(keyCode), shift: shift)
                    }
                }
            }
        }
        return map
    }

    public func output(text: String) async throws {
        let source = CGEventSource(stateID: .hidSystemState)
        // Resolve against the active layout first, then the static US map.
        // The Text Input Source APIs assert they run on the main thread, but
        // output() is driven from the async dictation pipeline (a background
        // thread) — so build the layout map on the main actor to avoid a
        // HIToolbox SIGTRAP. The actual key posting stays off-main so the long
        // per-character sleeps don't block the UI.
        let layoutMap = await MainActor.run { Self.layoutKeyMap() }

        for ch in text {
            if let mapping = layoutMap[ch] ?? Self.keyMap[ch] {
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: mapping.keyCode, keyDown: false) else {
                    continue
                }
                if mapping.shift {
                    keyDown.flags = .maskShift
                    keyUp.flags = .maskShift
                }
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            } else {
                // Fallback: clipboard paste for unmapped characters
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(String(ch), forType: .string)

                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
                    continue
                }
                keyDown.flags = .maskCommand
                keyUp.flags = .maskCommand
                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
            usleep(5000)
        }
    }
}
