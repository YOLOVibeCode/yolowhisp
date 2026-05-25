import Carbon.HIToolbox
import Cocoa

/// Comprehensive key code to human-readable name mapping.
/// Covers Mac built-in, external Mac, and Windows/PC keyboards.
public enum KeyCodeMap {

    /// Returns a human-readable name for any key code.
    public static func name(for keyCode: UInt16, modifiers: UInt = 0) -> String {
        // Check special keys first
        if let special = specialKeys[keyCode] {
            return special
        }

        // Try to get the character from the key code via the input source
        if let char = characterForKeyCode(keyCode) {
            return char.uppercased()
        }

        return "Key(\(keyCode))"
    }

    /// Returns a formatted string like "⌃⇧A" or "Globe" for display.
    public static func displayString(keyCode: UInt16, modifiers: UInt) -> String {
        var parts: [String] = []

        if modifiers & NSEvent.ModifierFlags.control.rawValue != 0 { parts.append("⌃") }
        if modifiers & NSEvent.ModifierFlags.option.rawValue != 0 { parts.append("⌥") }
        if modifiers & NSEvent.ModifierFlags.shift.rawValue != 0 { parts.append("⇧") }
        if modifiers & NSEvent.ModifierFlags.command.rawValue != 0 { parts.append("⌘") }

        let keyName = name(for: keyCode)

        // Don't duplicate modifier names if key is modifier-only
        if isModifierOnlyKey(keyCode) && !parts.isEmpty {
            // Key is a modifier that's already shown in the modifier symbols
            // Only show it standalone if no other modifiers
        }

        parts.append(keyName)
        return parts.joined()
    }

    /// Whether this key code represents a special key that fires as flagsChanged
    public static func isFlagsChangedKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55:    return true  // Right/Left Command
        case 56, 60:    return true  // Left/Right Shift
        case 58, 61:    return true  // Left/Right Option
        case 59, 62:    return true  // Left/Right Control
        case 57:        return true  // Caps Lock
        case 63:        return true  // Fn/Globe
        default:        return false
        }
    }

    /// Whether this is a modifier-only key (no character output)
    public static func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        isFlagsChangedKey(keyCode)
    }

    /// The virtual key code for Globe/Fn (what we store internally)
    public static let globeKeyCode: UInt16 = 179

    /// The actual keyCode macOS reports for the Fn/Globe physical key
    public static let fnPhysicalKeyCode: UInt16 = 63

    /// Check if an event matches Globe key press
    public static func isGlobeKeyEvent(_ event: NSEvent) -> Bool {
        event.type == .flagsChanged &&
        event.keyCode == fnPhysicalKeyCode &&
        (event.modifierFlags.rawValue & NSEvent.ModifierFlags.function.rawValue) != 0
    }

    /// Check if an event matches Globe key release
    public static func isGlobeKeyRelease(_ event: NSEvent) -> Bool {
        event.type == .flagsChanged &&
        event.keyCode == fnPhysicalKeyCode &&
        (event.modifierFlags.rawValue & NSEvent.ModifierFlags.function.rawValue) == 0
    }

    // MARK: - Private

    /// Get the character for a key code from the current keyboard layout
    private static func characterForKeyCode(_ keyCode: UInt16) -> String? {
        let source = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        guard let layoutDataRef = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = unsafeBitCast(layoutDataRef, to: CFData.self) as Data
        var deadKeyState: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0

        let result = layoutData.withUnsafeBytes { ptr -> OSStatus in
            guard let basePtr = ptr.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return errSecInternalError
            }
            return UCKeyTranslate(
                basePtr,
                keyCode,
                UInt16(kUCKeyActionDown),
                0, // no modifiers
                UInt32(LMGetKbdType()),
                UInt32(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
        }

        guard result == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }

    // MARK: - Key Code Table

    /// Comprehensive mapping of Mac key codes to names.
    /// Sources: Events.h, Carbon HIToolbox, empirical testing with various keyboards.
    private static let specialKeys: [UInt16: String] = [
        // Letters are handled by characterForKeyCode

        // Navigation
        36: "Return",
        48: "Tab",
        49: "Space",
        51: "Delete",
        53: "Escape",
        71: "Clear",
        76: "Enter",       // Numpad Enter
        117: "Forward Delete",

        // Arrow keys
        123: "Left Arrow",
        124: "Right Arrow",
        125: "Down Arrow",
        126: "Up Arrow",

        // Page navigation
        115: "Home",
        116: "Page Up",
        119: "End",
        121: "Page Down",

        // Function keys
        122: "F1",
        120: "F2",
        99:  "F3",
        118: "F4",
        96:  "F5",
        97:  "F6",
        98:  "F7",
        100: "F8",
        101: "F9",
        109: "F10",
        103: "F11",
        111: "F12",
        105: "F13",
        107: "F14",
        113: "F15",
        106: "F16",
        64:  "F17",
        79:  "F18",
        80:  "F19",
        90:  "F20",

        // Numpad
        65:  "Numpad .",
        67:  "Numpad *",
        69:  "Numpad +",
        75:  "Numpad /",
        78:  "Numpad -",
        81:  "Numpad =",
        82:  "Numpad 0",
        83:  "Numpad 1",
        84:  "Numpad 2",
        85:  "Numpad 3",
        86:  "Numpad 4",
        87:  "Numpad 5",
        88:  "Numpad 6",
        89:  "Numpad 7",
        91:  "Numpad 8",
        92:  "Numpad 9",

        // Modifier keys (when used standalone)
        54:  "Right Command",
        55:  "Left Command",
        56:  "Left Shift",
        57:  "Caps Lock",
        58:  "Left Option",
        59:  "Left Control",
        60:  "Right Shift",
        61:  "Right Option",
        62:  "Right Control",
        63:  "Globe",        // Fn/Globe physical key

        // Our internal Globe representation
        179: "Globe",

        // Media keys (varies by keyboard)
        // These often come through as system-defined events rather than key codes
        // but some keyboards/drivers report them as regular keys
    ]
}
