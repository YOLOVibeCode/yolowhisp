import Foundation

public enum TriggerMode: String, Codable {
    case hold
    case toggle
    case doubleTap
}

public struct HotkeyConfig: Equatable, Hashable, Codable {
    public let keyCode: UInt16
    public let modifiers: UInt
    public let triggerMode: TriggerMode
    public let outputMode: OutputMode
    public let postProcessEnabled: Bool
    public let modelOverride: String?

    public init(keyCode: UInt16, modifiers: UInt, triggerMode: TriggerMode = .hold,
                outputMode: OutputMode = .simulatedKeystrokes, postProcessEnabled: Bool = false,
                modelOverride: String? = nil) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.triggerMode = triggerMode
        self.outputMode = outputMode
        self.postProcessEnabled = postProcessEnabled
        self.modelOverride = modelOverride
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers)
    }

    public static func == (lhs: HotkeyConfig, rhs: HotkeyConfig) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers == rhs.modifiers &&
        lhs.triggerMode == rhs.triggerMode && lhs.outputMode == rhs.outputMode &&
        lhs.postProcessEnabled == rhs.postProcessEnabled && lhs.modelOverride == rhs.modelOverride
    }
}
