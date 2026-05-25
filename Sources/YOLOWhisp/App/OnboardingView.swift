import SwiftUI
import Cocoa

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 179
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = 0
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
        switch tag {
        case "globe":
            hotkeyKeyCode = 179
            hotkeyModifiers = 0
        case "ctrlshift":
            hotkeyKeyCode = 56
            hotkeyModifiers = Int(NSEvent.ModifierFlags.control.rawValue | NSEvent.ModifierFlags.shift.rawValue)
        case "f5":
            hotkeyKeyCode = 96
            hotkeyModifiers = 0
        default:
            break
        }
    }
}
