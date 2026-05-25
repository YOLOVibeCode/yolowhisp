import Cocoa

/// Records a hotkey from any keyboard — Mac built-in, external Mac, Windows/PC keyboards.
/// Handles regular keys, function keys, modifier-only keys, Globe/Fn, Caps Lock, and
/// numpad keys. Uses both local and global monitors for maximum coverage.
public final class HotkeyRecorderController: HotkeyRecording {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var flagsMonitor: Any?
    private var completion: ((HotkeyConfig) -> Void)?
    public private(set) var isRecording: Bool = false

    /// When recording, stores raw event info for debugging
    public private(set) var lastRawKeyCode: UInt16 = 0
    public private(set) var lastRawModifiers: UInt = 0
    public private(set) var lastEventType: String = ""

    public init() {}

    public func startRecording(completion: @escaping (HotkeyConfig) -> Void) {
        self.completion = completion
        isRecording = true

        // Monitor regular key presses (local — when our window is focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            self.handleKeyDown(event)
            return nil // swallow
        }

        // Monitor regular key presses (global — when another app is focused)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyDown(event)
        }

        // Monitor modifier/flags changes — catches Globe, Caps Lock, standalone modifiers
        // Use both local and global
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            guard let self = self else { return event }
            if self.handleFlagsChanged(event) {
                return nil // swallow
            }
            return event
        }

        // Global flags monitor
        let globalFlags = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        // Store the global flags monitor alongside flagsMonitor
        objc_setAssociatedObject(self, "globalFlagsMonitor", globalFlags, .OBJC_ASSOCIATION_RETAIN)
    }

    public func cancelRecording() {
        stopAllMonitors()
        isRecording = false
        completion = nil
    }

    // MARK: - Event Handling

    private func handleKeyDown(_ event: NSEvent) {
        let keyCode = event.keyCode
        let modifiers = event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue

        lastRawKeyCode = keyCode
        lastRawModifiers = UInt(modifiers)
        lastEventType = "keyDown"

        let config = HotkeyConfig(keyCode: keyCode, modifiers: UInt(modifiers))
        finishRecording(config)
    }

    @discardableResult
    private func handleFlagsChanged(_ event: NSEvent) -> Bool {
        let keyCode = event.keyCode

        lastRawKeyCode = keyCode
        lastRawModifiers = event.modifierFlags.rawValue
        lastEventType = "flagsChanged"

        // Globe/Fn key
        if keyCode == KeyCodeMap.fnPhysicalKeyCode {
            let fnPressed = (event.modifierFlags.rawValue & NSEvent.ModifierFlags.function.rawValue) != 0
            if fnPressed {
                let config = HotkeyConfig(keyCode: KeyCodeMap.globeKeyCode, modifiers: 0)
                finishRecording(config)
                return true
            }
            return false
        }

        // Caps Lock
        if keyCode == 57 {
            let config = HotkeyConfig(keyCode: 57, modifiers: 0)
            finishRecording(config)
            return true
        }

        // Standalone modifier keys (Shift, Control, Option, Command)
        // Only register on key-down (flag added), not key-up (flag removed)
        if KeyCodeMap.isFlagsChangedKey(keyCode) {
            // Check if this is a press (modifier flag present) vs release
            let isPress: Bool
            switch keyCode {
            case 56, 60: // Shift
                isPress = event.modifierFlags.contains(.shift)
            case 58, 61: // Option
                isPress = event.modifierFlags.contains(.option)
            case 59, 62: // Control
                isPress = event.modifierFlags.contains(.control)
            case 54, 55: // Command
                isPress = event.modifierFlags.contains(.command)
            default:
                isPress = false
            }

            if isPress {
                // For standalone modifier: store the keyCode with no extra modifiers
                // (the modifier IS the key, not a modifier of another key)
                let config = HotkeyConfig(keyCode: keyCode, modifiers: 0)
                finishRecording(config)
                return true
            }
        }

        return false
    }

    private func finishRecording(_ config: HotkeyConfig) {
        stopAllMonitors()
        isRecording = false
        completion?(config)
        completion = nil
    }

    private func stopAllMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = flagsMonitor { NSEvent.removeMonitor(m); flagsMonitor = nil }
        if let m = objc_getAssociatedObject(self, "globalFlagsMonitor") {
            NSEvent.removeMonitor(m)
            objc_setAssociatedObject(self, "globalFlagsMonitor", nil, .OBJC_ASSOCIATION_RETAIN)
        }
    }

    deinit {
        stopAllMonitors()
    }
}
