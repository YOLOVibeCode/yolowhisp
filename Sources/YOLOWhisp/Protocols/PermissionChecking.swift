import Foundation

public protocol PermissionChecking: AnyObject {
    func checkMicrophonePermission() -> Bool
    func requestMicrophonePermission() async -> Bool
    func checkAccessibilityPermission() -> Bool
    func requestAccessibilityPermission() -> Bool
    func openAccessibilitySettings()
}
