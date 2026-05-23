import Foundation

public enum OutputMode: String, Codable {
    case clipboardPaste
    case simulatedKeystrokes
    case accessibilityInsertion
    case clipboardOnly
}
