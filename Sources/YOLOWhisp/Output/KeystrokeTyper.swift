import Foundation
import Carbon.HIToolbox
import AppKit

public final class KeystrokeTyper: TextOutputting {
    public let mode: OutputMode = .simulatedKeystrokes
    public var typingSpeed: TypingSpeed = .medium
    
    /// Controls how characters are emitted: `.unicode` (lossless, for local apps)
    /// or `.keyCode` (hardware-faithful, for RDP/VM clients).
    public enum KeyEmission {
        case unicode
        case keyCode
    }
    public var emission: KeyEmission = .unicode
    
    public init(typingSpeed: TypingSpeed = .medium, emission: KeyEmission = .unicode) {
        self.typingSpeed = typingSpeed
        self.emission = emission
    }

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

    // MARK: - Thread-safe cached layout map
    //
    // `layoutKeyMap()` calls Text Input Source APIs that ASSERT they run on the
    // main thread (a hard SIGTRAP otherwise). The dictation pipeline runs off
    // the main thread, so we cache a snapshot built on the main thread and let
    // any thread read it lock-protected. This removes the previous
    // `DispatchQueue.main.sync` hop (a deadlock risk from Swift's cooperative
    // pool) from the hot path entirely.
    private static let layoutLock = NSLock()
    nonisolated(unsafe) private static var cachedLayout: [Character: KeyMapping] = [:]

    /// Build the current layout map and cache it. MUST be called on the main
    /// thread (TIS requirement). Call once at launch and whenever the active
    /// keyboard input source changes.
    public static func refreshLayoutCache() {
        let map = layoutKeyMap()
        layoutLock.lock()
        cachedLayout = map
        layoutLock.unlock()
    }

    /// The last layout map computed on the main thread. Safe to call from any
    /// thread. Empty until `refreshLayoutCache()` has run, in which case callers
    /// fall back to the static US `keyMap` (covers all printable ASCII).
    public static func cachedLayoutKeyMap() -> [Character: KeyMapping] {
        layoutLock.lock()
        defer { layoutLock.unlock() }
        return cachedLayout
    }

    /// A single planned keystroke. Either inserts a literal character via its
    /// Unicode value (layout/shift independent) or presses a real virtual key
    /// (used for Return / Tab so they behave like a physical press).
    public enum TypedKey: Equatable {
        case unicode(String)
        case virtualKey(CGKeyCode)
    }

    public static let returnKeyCode: CGKeyCode = 36
    public static let tabKeyCode: CGKeyCode = 48

    /// Pure mapping from text to the keystrokes we will emit. Separated from
    /// posting so typing fidelity can be verified deterministically in tests.
    public static func plan(for text: String) -> [TypedKey] {
        text.map { ch in
            switch ch {
            case "\n", "\r": return .virtualKey(returnKeyCode)
            case "\t":       return .virtualKey(tabKeyCode)
            default:         return .unicode(String(ch))
            }
        }
    }

    /// Reconstruct the exact text a plan would produce. Because printable
    /// characters are emitted as their literal Unicode value, this round-trips
    /// the input perfectly — the property our fidelity tests assert.
    public static func text(from plan: [TypedKey]) -> String {
        var out = ""
        for key in plan {
            switch key {
            case .unicode(let s):                 out += s
            case .virtualKey(Self.returnKeyCode): out += "\n"
            case .virtualKey(Self.tabKeyCode):    out += "\t"
            case .virtualKey:                     break
            }
        }
        return out
    }
    
    /// Returns true if every character in `text` can be typed via key codes
    /// (either in the layout map, the static US map, or is space/tab/newline).
    /// Used to decide whether keyCode emission is viable or if we must fall back
    /// to clipboard paste for characters not reachable via keyboard.
    ///
    /// Thread-safe: reads the cached layout snapshot (built on the main thread
    /// via `refreshLayoutCache()`), so this can be called from any thread with
    /// no main-thread hop. Falls back to the static US `keyMap`.
    public static func isFullyMappable(_ text: String) -> Bool {
        let layout = cachedLayoutKeyMap()
        
        for ch in text {
            // Return, tab, newline are always real keys
            if ch == "\n" || ch == "\r" || ch == "\t" {
                continue
            }
            // Check if character exists in either the layout map or the static US map
            if layout[ch] == nil && keyMap[ch] == nil {
                return false
            }
        }
        return true
    }

    public func output(text: String) async throws {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }

        switch emission {
        case .unicode:
            // Current behavior: lossless Unicode injection for local apps
            for key in Self.plan(for: text) {
                switch key {
                case .unicode(let s):       postUnicode(source: source, s)
                case .virtualKey(let code): postKey(source: source, keyCode: code)
                }
                usleep(typingSpeed.delayMicroseconds)
            }
            
        case .keyCode:
            // Hardware-faithful: emit real key codes + explicit Shift events
            // for RDP/VM clients that forward only key codes, not Unicode strings.
            
            // Read the cached layout snapshot (built on the main thread). No
            // main-thread hop here keeps typing off the main run loop.
            let layout = Self.cachedLayoutKeyMap()
            
            for ch in text {
                // Handle special keys
                if ch == "\n" || ch == "\r" {
                    postKey(source: source, keyCode: Self.returnKeyCode)
                    usleep(typingSpeed.delayMicroseconds)
                    continue
                }
                if ch == "\t" {
                    postKey(source: source, keyCode: Self.tabKeyCode)
                    usleep(typingSpeed.delayMicroseconds)
                    continue
                }
                
                // Resolve (keyCode, needsShift) from layout or fall back to US map
                guard let mapping = layout[ch] ?? Self.keyMap[ch] else {
                    // Character not mappable (emoji, etc.) — skip it.
                    // Caller should use isFullyMappable to avoid this path.
                    continue
                }
                
                postKeyCode(source: source, keyCode: mapping.keyCode, needsShift: mapping.shift)
                usleep(typingSpeed.delayMicroseconds)
            }
        }
    }

    /// Post a keystroke that inserts the given literal string (layout-independent).
    private func postUnicode(source: CGEventSource, _ string: String) {
        let utf16 = Array(string.utf16)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            return
        }
        // Clear any inherited modifier flags from the system event source so a
        // physically-held key (or stale state) can't alter the inserted text.
        keyDown.flags = []
        keyUp.flags = []
        keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Post a real virtual key (used for Return / Tab) with no modifiers.
    private func postKey(source: CGEventSource, keyCode: CGKeyCode) {
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = []
        keyUp.flags = []
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
    
    /// Post a character key code with explicit Shift down/up events when needed.
    /// This is the hardware-faithful sequence that RDP/VM clients forward correctly.
    /// Small delays between events ensure RDP has time to process each keystroke.
    private func postKeyCode(source: CGEventSource, keyCode: CGKeyCode, needsShift: Bool) {
        let shiftKeyCode: CGKeyCode = 56  // kVK_Shift
        let microDelay: UInt32 = 1000  // 1ms between modifier and key events
        
        if needsShift {
            // Press Shift
            if let shiftDown = CGEvent(keyboardEventSource: source, virtualKey: shiftKeyCode, keyDown: true) {
                shiftDown.flags = .maskShift
                shiftDown.post(tap: .cghidEventTap)
                usleep(microDelay)  // Give RDP time to register Shift down
            }
        }
        
        // Press character key
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return
        }
        keyDown.flags = needsShift ? .maskShift : []
        keyUp.flags = needsShift ? .maskShift : []
        keyDown.post(tap: .cghidEventTap)
        usleep(microDelay)  // Brief pause between down and up
        keyUp.post(tap: .cghidEventTap)
        
        if needsShift {
            usleep(microDelay)  // Pause before releasing Shift
            // Release Shift
            if let shiftUp = CGEvent(keyboardEventSource: source, virtualKey: shiftKeyCode, keyDown: false) {
                shiftUp.flags = []
                shiftUp.post(tap: .cghidEventTap)
            }
        }
    }
}
