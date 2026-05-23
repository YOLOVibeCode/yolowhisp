import SwiftUI

struct SettingsView: View {
    @AppStorage("outputMode") private var outputMode: String = OutputMode.simulatedKeystrokes.rawValue
    @AppStorage("whisperModel") private var whisperModel: String = "base"
    @AppStorage("aiPolishEnabled") private var aiPolishEnabled: Bool = false
    @AppStorage("aiProvider") private var aiProvider: String = ProviderType.ollama.rawValue
    @AppStorage("aiModelName") private var aiModelName: String = ""
    @AppStorage("aiApiKey") private var aiApiKey: String = ""
    @AppStorage("retentionDays") private var retentionDays: Int = 30

    var body: some View {
        Form {
            Section("Hotkey") {
                HStack {
                    Text("Current shortcut: Globe (double-tap)")
                    Spacer()
                    Button("Record New...") {}
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
}
