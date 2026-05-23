import AppKit
import SwiftUI

public final class PillViewController: PillDisplaying {
    public private(set) var currentState: PillState = .idle
    public var isVisible: Bool { panel?.isVisible ?? false }

    public var position: CGPoint {
        get {
            guard let panel = panel else {
                return CGPoint(
                    x: userDefaults.double(forKey: "yolowhisp.pill.x"),
                    y: userDefaults.double(forKey: "yolowhisp.pill.y")
                )
            }
            return panel.frame.origin
        }
        set {
            userDefaults.set(Double(newValue.x), forKey: "yolowhisp.pill.x")
            userDefaults.set(Double(newValue.y), forKey: "yolowhisp.pill.y")
            panel?.setFrameOrigin(NSPoint(x: newValue.x, y: newValue.y))
        }
    }

    public var dragController: PillDragController?
    public var audioLevel: Float = 0.0

    public private(set) var panel: NSPanel?
    private let userDefaults: UserDefaults

    public var pillColor: NSColor {
        switch currentState {
        case .idle: return .darkGray
        case .recording: return .systemRed
        case .processing: return .systemBlue
        case .dragMode: return .darkGray
        }
    }

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func show() {
        if panel == nil { createPanel() }
        panel?.orderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
    }

    public func setState(_ state: PillState) {
        currentState = state
        updatePillView()
    }

    private func createPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: PillView(state: currentState, audioLevel: audioLevel))
        panel.contentView = hostingView

        let x = userDefaults.double(forKey: "yolowhisp.pill.x")
        let y = userDefaults.double(forKey: "yolowhisp.pill.y")
        if x != 0 || y != 0 {
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }

        self.panel = panel
    }

    private func updatePillView() {
        guard let panel = panel else { return }
        let hostingView = NSHostingView(rootView: PillView(state: currentState, audioLevel: audioLevel))
        panel.contentView = hostingView
    }
}
