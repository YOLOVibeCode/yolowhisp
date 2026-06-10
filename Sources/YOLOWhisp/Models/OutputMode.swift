import Foundation

public enum OutputMode: String, Codable {
    case clipboardPaste
    case simulatedKeystrokes
    case accessibilityInsertion
    case clipboardOnly
    case remoteKeystrokes          // Key-code emulation for RDP/VM (auto-selected)
    case remoteClipboardPaste      // Ctrl+V paste for unmappable chars in RDP/VM (auto-selected)
}
