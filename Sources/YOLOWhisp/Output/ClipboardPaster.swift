import AppKit
import Carbon.HIToolbox

public final class ClipboardPaster: TextOutputting {
    public let mode: OutputMode = .clipboardPaste

    /// Whether to restore the user's previous clipboard contents after pasting.
    /// Mutable so the app can update it live from Settings.
    public var restoresClipboard: Bool
    /// Delay before restoring, giving the simulated paste time to land first.
    /// Mutable so the app can update it live from Settings.
    public var restoreDelay: TimeInterval
    /// Modifier key for paste: .maskCommand (Cmd+V for macOS) or .maskControl (Ctrl+V for RDP/Windows).
    /// Mutable so the controller can switch based on target app detection.
    public var pasteModifier: CGEventFlags

    public init(
        restoresClipboard: Bool = true,
        restoreDelay: TimeInterval = 0.4,
        pasteModifier: CGEventFlags = .maskCommand
    ) {
        self.restoresClipboard = restoresClipboard
        self.restoreDelay = restoreDelay
        self.pasteModifier = pasteModifier
    }

    public func output(text: String) async throws {
        let pasteboard = NSPasteboard.general

        // Stage the exact text and snapshot what the user had (as plain Data
        // keyed by type) so we can put it back after pasting.
        let saved = Self.stage(text: text, on: pasteboard)
        let restoreSaved = restoresClipboard ? saved : []

        // Simulate paste shortcut (Cmd+V for macOS, Ctrl+V for RDP/Windows)
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = pasteModifier
        keyUp.flags = pasteModifier

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Restore the prior clipboard once the paste has had time to complete.
        if restoresClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                Self.restore(restoreSaved)
            }
        }
    }

    /// Stage `text` for pasting on the given pasteboard, returning a snapshot of
    /// the prior contents so they can be restored afterward. Separated from the
    /// Cmd+V side effect so clipboard fidelity is verifiable in tests.
    @discardableResult
    static func stage(text: String, on pasteboard: NSPasteboard) -> [[String: Data]] {
        let saved = snapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        return saved
    }

    /// Copy every item/type currently on the pasteboard into a Sendable form.
    static func snapshot(_ pasteboard: NSPasteboard) -> [[String: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [String: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type.rawValue] = data
                }
            }
            return dict
        }
    }

    /// Rebuild pasteboard items from a snapshot and write them back.
    static func restore(_ saved: [[String: Data]], to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (rawType, data) in dict {
                item.setData(data, forType: NSPasteboard.PasteboardType(rawType))
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
