import Foundation

public protocol HotkeyListening {
    func register(hotkey: HotkeyConfig, handler: @escaping () -> Void)
    func register(hotkey: HotkeyConfig, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void)
    func unregister(hotkey: HotkeyConfig)
}
