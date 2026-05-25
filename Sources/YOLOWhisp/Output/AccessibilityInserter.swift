import ApplicationServices
import Foundation

public final class AccessibilityInserter: TextOutputting {
    public let mode: OutputMode = .accessibilityInsertion
    public init() {}

    public func output(text: String) async throws {
        guard AXIsProcessTrusted() else {
            throw TextOutputError.accessibilityNotGranted
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        // Verify the returned value really is an AXUIElement before casting.
        // Force-casting an unexpected CFTypeRef here would crash the app.
        guard focusResult == .success, let element = focusedElement,
              CFGetTypeID(element) == AXUIElementGetTypeID() else {
            throw TextOutputError.noFocusedElement
        }
        let axElement = element as! AXUIElement

        // Preferred path: replace the current selection / insert at the caret.
        // This is what a dictation tool wants — it respects cursor position and
        // doesn't clobber text the user already typed in the field.
        let selectedResult = AXUIElementSetAttributeValue(
            axElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef
        )
        if selectedResult == .success {
            return
        }

        // Fallback for elements that don't support selected-text insertion:
        // append to the existing value.
        var currentValue: AnyObject?
        AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)

        let existing = (currentValue as? String) ?? ""
        let newValue = existing + text

        let setResult = AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newValue as CFTypeRef)
        guard setResult == .success else {
            throw TextOutputError.failedToSetValue
        }
    }
}
