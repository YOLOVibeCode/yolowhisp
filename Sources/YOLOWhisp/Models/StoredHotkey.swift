import Foundation

/// A hotkey entry stored in user defaults. Supports multiple hotkeys.
public struct StoredHotkey: Codable, Identifiable, Equatable {
    public var id: UUID
    public var keyCode: Int
    public var modifiers: Int
    public var triggerMode: String  // TriggerMode rawValue

    public init(keyCode: Int = 179, modifiers: Int = 0, triggerMode: String = "hold") {
        self.id = UUID()
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.triggerMode = triggerMode
    }

    public var displayName: String {
        KeyCodeMap.displayString(keyCode: UInt16(keyCode), modifiers: UInt(modifiers))
    }

    public var config: HotkeyConfig {
        HotkeyConfig(
            keyCode: UInt16(keyCode),
            modifiers: UInt(modifiers),
            triggerMode: TriggerMode(rawValue: triggerMode) ?? .hold
        )
    }

    /// Encode an array to JSON string for AppStorage
    public static func encode(_ hotkeys: [StoredHotkey]) -> String {
        (try? String(data: JSONEncoder().encode(hotkeys), encoding: .utf8)) ?? "[]"
    }

    /// Decode from JSON string
    public static func decode(_ json: String) -> [StoredHotkey] {
        guard let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode([StoredHotkey].self, from: data) else {
            return [StoredHotkey()]  // default: Globe key
        }
        return result.isEmpty ? [StoredHotkey()] : result
    }
}
