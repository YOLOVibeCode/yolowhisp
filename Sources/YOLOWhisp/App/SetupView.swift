import SwiftUI
import Cocoa

/// First-run setup: friendly framing over the shared HealthCheckView (which
/// offers one-click fixes + "Set up everything"), plus a hotkey picker and a
/// gated "Get Started".
struct SetupView: View {
    let services: AppServices
    var onDone: () -> Void = {}

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("hotkeys") private var hotkeysJSON: String = StoredHotkey.encode([StoredHotkey()])
    @State private var selectedShortcut = "globe"

    @State private var micOK = false
    @State private var axOK = false
    @State private var whisperOK = false
    @State private var modelOK = false

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()
    private var ready: Bool { micOK && axOK && whisperOK && modelOK }

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("Welcome to YOLOWhisp").font(.largeTitle).fontWeight(.bold)
                Text("Let's get everything set up. Use the fixes below — or “Set up everything”.")
                    .font(.callout).foregroundColor(.secondary)
            }
            .padding(.top, 16)

            HealthCheckView(services: services, friendly: true)
                .frame(maxHeight: .infinity)

            GroupBox("Dictation shortcut") {
                HStack(spacing: 10) {
                    shortcut("Globe", "globe", "globe")
                    shortcut("Ctrl+Shift", "ctrlshift", "command")
                    shortcut("F5", "f5", "keyboard")
                    shortcut("Custom", "custom", "gearshape")
                }.padding(.vertical, 6)
            }
            .padding(.horizontal, 16)

            Button("Get Started") {
                hasCompletedOnboarding = true
                onDone()
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(!ready)
            .help(ready ? "" : "Grant permissions, install whisper-cli, and load a model first")
            .padding(.bottom, 16)
        }
        .frame(width: 600, height: 640)
        .onAppear(perform: refresh)
        .onReceive(timer) { _ in refresh() }
    }

    private func shortcut(_ label: String, _ tag: String, _ symbol: String) -> some View {
        Button {
            selectedShortcut = tag
            applyPreset(tag)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.title3)
                Text(label).font(.caption2)
            }
            .frame(width: 72, height: 52)
        }
        .buttonStyle(.bordered)
        .tint(selectedShortcut == tag ? .accentColor : .secondary)
    }

    private func applyPreset(_ tag: String) {
        let hotkey: StoredHotkey?
        switch tag {
        case "globe":     hotkey = StoredHotkey(keyCode: 179, modifiers: 0, triggerMode: "hold")
        case "ctrlshift": hotkey = StoredHotkey(keyCode: 56,
                              modifiers: Int(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue),
                              triggerMode: "hold")
        case "f5":        hotkey = StoredHotkey(keyCode: 96, modifiers: 0, triggerMode: "toggle")
        default:          hotkey = nil // custom: configure later in Settings
        }
        if let hotkey { hotkeysJSON = StoredHotkey.encode([hotkey]) }
    }

    private func refresh() {
        micOK = services.permissions.checkMicrophonePermission()
        axOK = services.permissions.checkAccessibilityPermission()
        whisperOK = FileManager.default.fileExists(atPath: services.whisperPath)
        modelOK = services.modelManager.currentModel != nil || !services.modelManager.availableModels().isEmpty
    }
}
