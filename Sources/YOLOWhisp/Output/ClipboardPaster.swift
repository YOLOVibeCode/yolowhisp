import AppKit
import Carbon.HIToolbox

public final class ClipboardPaster: TextOutputting {
    public let mode: OutputMode = .clipboardPaste

    /// Whether to restore the user's previous clipboard contents after pasting.
    private let restoresClipboard: Bool
    /// Delay before restoring, giving the simulated Cmd+V time to land first.
    private let restoreDelay: TimeInterval

    public init(restoresClipboard: Bool = true, restoreDelay: TimeInterval = 0.4) {
        self.restoresClipboard = restoresClipboard
        self.restoreDelay = restoreDelay
    }

    public func output(text: String) async throws {
        let pasteboard = NSPasteboard.general

        // Snapshot what the user had (as plain Data keyed by type) so we can
        // put it back after pasting.
        let saved = restoresClipboard ? Self.snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        // Restore the prior clipboard once the paste has had time to complete.
        if restoresClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                Self.restore(saved)
            }
        }
    }

    /// Copy every item/type currently on the pasteboard into a Sendable form.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [[String: Data]] {
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
    private static func restore(_ saved: [[String: Data]]) {
        let pasteboard = NSPasteboard.general
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
