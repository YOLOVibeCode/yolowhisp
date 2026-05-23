import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var selectedShortcut: String = "globe"
    @State private var micPermission: Bool = false
    @State private var accessibilityPermission: Bool = false

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
                                // Request mic permission
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
                                // Open System Settings
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
        }
        .padding(40)
        .frame(width: 500, height: 450)
    }

    private func shortcutButton(_ label: String, tag: String, symbol: String) -> some View {
        Button {
            selectedShortcut = tag
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
}
