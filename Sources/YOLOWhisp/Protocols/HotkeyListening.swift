import Foundation

public protocol HotkeyListening {
    func register(hotkey: HotkeyConfig, handler: @escaping () -> Void)
    func unregister(hotkey: HotkeyConfig)
}
