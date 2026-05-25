import SwiftUI
import Cocoa

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    // Live hotkey registration reads this key (the StoredHotkey array), so the
    // preset must be written here — not the legacy hotkeyKeyCode/Modifiers keys.
    @AppStorage("hotkeys") private var hotkeysJSON: String = StoredHotkey.encode([StoredHotkey()])
    @State private var selectedShortcut: String = "globe"
    @State private var micPermission: Bool = false
    @State private var accessibilityPermission: Bool = false

    let permissionChecker: any PermissionChecking

    private var canProceed: Bool {
        micPermission && accessibilityPermission
    }

    let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to YOLOWhisp")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Voice dictation powered by Whisper, right on your Mac.")
                .font(.title3)
                .foregroundStyle(.secondary)

            GroupBox("Pick your dictation shortcut") {
                HStack(spacing: 12) {
                    shortcutButton("Globe", tag: "globe", symbol: "globe")
                    shortcutButton("Ctrl+Shift", tag: "ctrlshift", symbol: "command")
                    shortcutButton("F5", tag: "f5", symbol: "keyboard")
                    shortcutButton("Custom", tag: "custom", symbol: "gearshape")
                }
                .padding(.vertical, 8)
            }

            GroupBox("Permissions") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: micPermission ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(micPermission ? .green : .red)
                        Text("Microphone Access")
                        Spacer()
                        if !micPermission {
                            Button("Grant") {
                                Task {
                                    let granted = await permissionChecker.requestMicrophonePermission()
                                    await MainActor.run { micPermission = granted }
                                }
                            }
                        }
                    }

                    HStack {
                        Image(systemName: accessibilityPermission ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundStyle(accessibilityPermission ? .green : .red)
                        Text("Accessibility Access")
                        Spacer()
                        if !accessibilityPermission {
                            Button("Grant") {
                                permissionChecker.openAccessibilitySettings()
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Spacer()

            Button("Get Started") {
                hasCompletedOnboarding = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canProceed)
        }
        .padding(40)
        .frame(width: 500, height: 450)
        .onAppear {
            micPermission = permissionChecker.checkMicrophonePermission()
            accessibilityPermission = permissionChecker.checkAccessibilityPermission()
        }
        .onReceive(timer) { _ in
            accessibilityPermission = permissionChecker.checkAccessibilityPermission()
            micPermission = permissionChecker.checkMicrophonePermission()
        }
    }

    private func shortcutButton(_ label: String, tag: String, symbol: String) -> some View {
        Button {
            selectedShortcut = tag
            applyPreset(tag)
        } label: {
            VStack {
                Image(systemName: symbol)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(width: 70, height: 60)
        }
        .buttonStyle(.bordered)
        .tint(selectedShortcut == tag ? .accentColor : .secondary)
    }

    private func applyPreset(_ tag: String) {
        let hotkey: StoredHotkey?
        switch tag {
        case "globe":
            hotkey = StoredHotkey(keyCode: 179, modifiers: 0, triggerMode: "hold")
        case "ctrlshift":
            hotkey = StoredHotkey(
                keyCode: 56,
                modifiers: Int(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue),
                triggerMode: "hold"
            )
        case "f5":
            hotkey = StoredHotkey(keyCode: 96, modifiers: 0, triggerMode: "toggle")
        default:
            // "custom" — leave the existing hotkey; user sets it in Settings.
            hotkey = nil
        }
        if let hotkey {
            hotkeysJSON = StoredHotkey.encode([hotkey])
        }
    }
}
