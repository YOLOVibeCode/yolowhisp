import Cocoa

public final class HotkeyRecorderController: HotkeyRecording {
    private var localMonitor: Any?
    private var completion: ((HotkeyConfig) -> Void)?
    public private(set) var isRecording: Bool = false

    public init() {}

    public func startRecording(completion: @escaping (HotkeyConfig) -> Void) {
        self.completion = completion
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            let modifiers = event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
            let config = HotkeyConfig(keyCode: event.keyCode, modifiers: UInt(modifiers))
            self.stopMonitor()
            self.isRecording = false
            self.completion?(config)
            self.completion = nil
            return nil // swallow the event
        }
    }

    public func cancelRecording() {
        stopMonitor()
        isRecording = false
        completion = nil
    }

    private func stopMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        stopMonitor()
    }
}
