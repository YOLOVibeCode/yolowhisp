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

    public func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
