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

        guard focusResult == .success, let element = focusedElement else {
            throw TextOutputError.noFocusedElement
        }

        let axElement = element as! AXUIElement

        // Get current value
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
