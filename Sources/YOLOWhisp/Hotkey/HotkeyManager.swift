import Cocoa

public final class HotkeyManager: HotkeyListening {
    private var handlers: [HotkeyConfig: () -> Void] = [:]
    private var globalMonitor: Any?

    public var registeredCount: Int { handlers.count }

    public init() {}

    public func register(hotkey: HotkeyConfig, handler: @escaping () -> Void) {
        handlers[hotkey] = handler
        startMonitoringIfNeeded()
    }

    public func unregister(hotkey: HotkeyConfig) {
        handlers.removeValue(forKey: hotkey)
        stopMonitoringIfEmpty()
    }

    public func unregisterAll() {
        handlers.removeAll()
        stopMonitoringIfEmpty()
    }

    private func startMonitoringIfNeeded() {
        guard globalMonitor == nil else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleEvent(event)
        }
    }

    private func stopMonitoringIfEmpty() {
        guard handlers.isEmpty, let monitor = globalMonitor else { return }
        NSEvent.removeMonitor(monitor)
        globalMonitor = nil
    }

    private func handleEvent(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue

        for (config, handler) in handlers {
            if config.keyCode == keyCode && config.modifiers == UInt(modifiers) {
                if config.triggerMode == .hold {
                    if event.type == .keyDown {
                        handler()
                    }
                } else {
                    if event.type == .keyDown {
                        handler()
                    }
                }
            }
        }
    }

    deinit {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
