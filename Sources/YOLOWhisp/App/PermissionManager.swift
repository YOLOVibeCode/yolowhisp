import AVFoundation
import Cocoa

public final class PermissionManager: PermissionChecking {
    public init() {}

    public func checkMicrophonePermission() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    public func requestMicrophonePermission() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    public func checkAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the native system prompt if not yet trusted, then returns the current status.
    /// Use this on startup or when the user taps "Grant Access" so macOS shows the dialog
    /// automatically rather than requiring the user to navigate System Settings manually.
    public func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
