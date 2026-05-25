import Cocoa

public final class HotkeyManager: HotkeyListening {
    private var handlers: [HotkeyConfig: () -> Void] = [:]
    private var keyUpHandlers: [HotkeyConfig: () -> Void] = [:]
    private var globalMonitor: Any?
    private var localMonitor: Any?

    public var registeredCount: Int { handlers.count }
    public var keyUpHandlerCount: Int { keyUpHandlers.count }

    /// Tracks which flagsChanged keys are currently pressed to detect press vs release
    private var pressedFlagKeys: Set<UInt16> = []

    public init() {}

    public func register(hotkey: HotkeyConfig, handler: @escaping () -> Void) {
        handlers[hotkey] = handler
        startMonitoringIfNeeded()
    }

    public func register(hotkey: HotkeyConfig, onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        handlers[hotkey] = onKeyDown
        keyUpHandlers[hotkey] = onKeyUp
        startMonitoringIfNeeded()
    }

    public func unregister(hotkey: HotkeyConfig) {
        handlers.removeValue(forKey: hotkey)
        keyUpHandlers.removeValue(forKey: hotkey)
        stopMonitoringIfEmpty()
    }

    public func unregisterAll() {
        handlers.removeAll()
        keyUpHandlers.removeAll()
        pressedFlagKeys.removeAll()
        stopMonitoringIfEmpty()
    }

    private func startMonitoringIfNeeded() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
        }
        // Also monitor locally so hotkeys work when our own windows are focused
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
            return event // don't swallow — let the UI still work
        }
    }

    private func stopMonitoringIfEmpty() {
        guard handlers.isEmpty && keyUpHandlers.isEmpty else { return }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
    }

    private func handleEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue

        for (config, handler) in handlers {
            // --- Globe/Fn key ---
            if config.keyCode == KeyCodeMap.globeKeyCode && event.type == .flagsChanged && keyCode == KeyCodeMap.fnPhysicalKeyCode {
                if KeyCodeMap.isGlobeKeyEvent(event) && !pressedFlagKeys.contains(keyCode) {
                    pressedFlagKeys.insert(keyCode)
                    handler()
                } else if KeyCodeMap.isGlobeKeyRelease(event) && pressedFlagKeys.contains(keyCode) {
                    pressedFlagKeys.remove(keyCode)
                    keyUpHandlers[config]?()
                }
                return
            }

            // --- Other flagsChanged keys (standalone modifiers, Caps Lock) ---
            if event.type == .flagsChanged && KeyCodeMap.isFlagsChangedKey(keyCode) {
                if config.keyCode == keyCode && config.modifiers == 0 {
                    let isPress = isFlagKeyPressed(keyCode, event: event)
                    if isPress && !pressedFlagKeys.contains(keyCode) {
                        pressedFlagKeys.insert(keyCode)
                        handler()
                    } else if !isPress && pressedFlagKeys.contains(keyCode) {
                        pressedFlagKeys.remove(keyCode)
                        keyUpHandlers[config]?()
                    }
                    return
                }
            }

            // --- Regular keys ---
            if config.keyCode == keyCode && config.modifiers == UInt(modifiers) {
                if event.type == .keyDown {
                    handler()
                } else if event.type == .keyUp {
                    keyUpHandlers[config]?()
                }
            }
        }
    }

    /// Determine if a modifier key is being pressed or released
    private func isFlagKeyPressed(_ keyCode: UInt16, event: NSEvent) -> Bool {
        switch keyCode {
        case 56, 60: return event.modifierFlags.contains(.shift)
        case 58, 61: return event.modifierFlags.contains(.option)
        case 59, 62: return event.modifierFlags.contains(.control)
        case 54, 55: return event.modifierFlags.contains(.command)
        case 57:     return event.modifierFlags.contains(.capsLock)
        case 63:     return (event.modifierFlags.rawValue & NSEvent.ModifierFlags.function.rawValue) != 0
        default:     return false
        }
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
    }
}
