import SwiftUI

struct SettingsView: View {
    @AppStorage("outputMode") private var outputMode: String = OutputMode.simulatedKeystrokes.rawValue
    @AppStorage("whisperModel") private var whisperModel: String = "base"
    @AppStorage("aiPolishEnabled") private var aiPolishEnabled: Bool = false
    @AppStorage("aiProvider") private var aiProvider: String = ProviderType.ollama.rawValue
    @AppStorage("aiModelName") private var aiModelName: String = ""
    @AppStorage("aiApiKey") private var aiApiKey: String = ""
    @AppStorage("retentionDays") private var retentionDays: Int = 30
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 49
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = 0

    @State private var isRecording: Bool = false
    private let recorder = HotkeyRecorderController()

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Current shortcut: \(hotkeyDescription)")
                    Spacer()
                    Button(isRecording ? "Press a key..." : "Record New...") {
                        isRecording = true
                        recorder.startRecording { config in
                            hotkeyKeyCode = Int(config.keyCode)
                            hotkeyModifiers = Int(config.modifiers)
                            isRecording = false
                        }
                    }
                    .disabled(isRecording)
                }
            }

            Section("Output Mode") {
                Picker("Mode", selection: $outputMode) {
                    Text("Clipboard Paste").tag(OutputMode.clipboardPaste.rawValue)
                    Text("Simulated Keystrokes").tag(OutputMode.simulatedKeystrokes.rawValue)
                    Text("Accessibility Insertion").tag(OutputMode.accessibilityInsertion.rawValue)
                }
            }

            Section("Whisper Model") {
                Picker("Model", selection: $whisperModel) {
                    Text("Tiny").tag("tiny")
                    Text("Base").tag("base")
                    Text("Small").tag("small")
                    Text("Medium").tag("medium")
                    Text("Large").tag("large")
                }
            }

            Section("AI Polish") {
                Toggle("Enable AI Polish", isOn: $aiPolishEnabled)

                if aiPolishEnabled {
                    Picker("Provider", selection: $aiProvider) {
                        Text("Ollama").tag(ProviderType.ollama.rawValue)
                        Text("OpenAI").tag(ProviderType.openai.rawValue)
                        Text("Anthropic").tag(ProviderType.anthropic.rawValue)
                        Text("Custom").tag(ProviderType.custom.rawValue)
                    }

                    TextField("Model Name", text: $aiModelName)

                    if aiProvider != ProviderType.ollama.rawValue {
                        SecureField("API Key", text: $aiApiKey)
                    }
                }
            }

            Section("History") {
                Picker("Retention", selection: $retentionDays) {
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 500)
        .padding()
    }

    private var hotkeyDescription: String {
        var parts: [String] = []
        let mods = UInt(hotkeyModifiers)
        if mods & NSEvent.ModifierFlags.control.rawValue != 0 { parts.append("⌃") }
        if mods & NSEvent.ModifierFlags.option.rawValue != 0 { parts.append("⌥") }
        if mods & NSEvent.ModifierFlags.shift.rawValue != 0 { parts.append("⇧") }
        if mods & NSEvent.ModifierFlags.command.rawValue != 0 { parts.append("⌘") }

        let keyName: String
        switch hotkeyKeyCode {
        case 49: keyName = "Space"
        case 96: keyName = "F5"
        case 179: keyName = "Globe"
        case 36: keyName = "Return"
        case 48: keyName = "Tab"
        case 53: keyName = "Escape"
        default: keyName = "Key(\(hotkeyKeyCode))"
        }
        parts.append(keyName)
        return parts.joined()
    }
}
