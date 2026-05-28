import Foundation

public enum TypingSpeed: String, Codable, CaseIterable {
    case fast
    case medium
    case slow
    
    public var delayMicroseconds: UInt32 {
        switch self {
        case .fast:
            return 2_000  // 2ms
        case .medium:
            return 5_000  // 5ms (current default)
        case .slow:
            return 15_000 // 15ms
        }
    }
    
    public var displayName: String {
        switch self {
        case .fast:
            return "Fast"
        case .medium:
            return "Medium"
        case .slow:
            return "Slow"
        }
    }
}
