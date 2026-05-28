import SwiftUI
import CoreAudio

struct SettingsView: View {
    /// Opens the Diagnostics window via the app's shared AppWindowStore
    /// (injected so it doesn't create an unretained window that crashes on close).
    var openDiagnostics: () -> Void = {}

    @AppStorage("outputMode") private var outputMode: String = OutputMode.simulatedKeystrokes.rawValue
    @AppStorage("whisperModel") private var whisperModel: String = "base"
    @AppStorage("aiPolishEnabled") private var aiPolishEnabled: Bool = false
    @AppStorage("dualOpinionEnabled") private var dualOpinionEnabled: Bool = false
    @AppStorage("dualMergeMethod") private var dualMergeMethod: String = "ai"
    @AppStorage("secondWhisperModel") private var secondWhisperModel: String = "small"
    @AppStorage("aiProvider") private var aiProvider: String = ProviderType.ollama.rawValue
    @AppStorage("aiModelName") private var aiModelName: String = ""
    @AppStorage("aiApiKey") private var aiApiKey: String = ""
    @AppStorage("retentionDays") private var retentionDays: Int = 30
    @AppStorage("hotkeys") private var hotkeysJSON: String = StoredHotkey.encode([StoredHotkey()])
    @State private var hotkeys: [StoredHotkey] = []
    @AppStorage("selectedMicrophoneID") private var selectedMicrophoneID: Int = 0
    @AppStorage("menuBarIcon") private var menuBarIconStyle: String = MenuBarIconStyle.whisperBubble.rawValue
    @AppStorage("soundStyle") private var soundStyle: String = SoundFeedback.SoundStyle.tinkPop.rawValue
    @AppStorage("typingSpeed") private var typingSpeed: String = TypingSpeed.medium.rawValue

    @State private var availableMicrophones: [(id: AudioDeviceID, name: String)] = []
    @State private var micTestLevel: Float = 0.0
    @State private var micTestEngine: AudioCaptureEngine?
    @State private var micTesting: Bool = false

    var body: some View {
        ScrollView {
        Form {
            // ── Hotkeys ───────────────────────────────
            Section("Hotkeys") {
                ForEach(hotkeys) { hotkey in
                    HStack {
                        Text(hotkey.displayName)
                            .font(.system(.body, design: .rounded))
                            .fontWeight(.medium)
                        Text("(\(hotkey.triggerMode))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
                Button {
                    openDiagnostics()
                } label: {
                    Label("Configure & Test", systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }

            Section("Sound Feedback") {
                Picker("Style", selection: $soundStyle) {
                    ForEach(SoundFeedback.SoundStyle.allCases) { style in
                        Text(style.displayName).tag(style.rawValue)
                    }
                }
                .onChange(of: soundStyle) { _, newValue in
                    let style = SoundFeedback.SoundStyle(rawValue: newValue) ?? .tinkPop
                    SoundFeedback.shared.setStyle(style)
                }
                HStack {
                    Button("Preview Start") {
                        SoundFeedback.shared.playStart()
                    }
                    .controlSize(.small)
                    Button("Preview Stop") {
                        SoundFeedback.shared.playStop()
                    }
                    .controlSize(.small)
                }
            }

            Section("Microphone") {
                Picker("Input Source", selection: $selectedMicrophoneID) {
                    Text("System Default").tag(0)
                    ForEach(availableMicrophones, id: \.id) { mic in
                        Text(mic.name).tag(Int(mic.id))
                    }
                }
                .onChange(of: selectedMicrophoneID) { _, _ in
                    if micTesting { restartMicTest() }
                }

                HStack {
                    AudioLevelMeter(level: micTestLevel)
                        .frame(height: 22)
                        .animation(.easeOut(duration: 0.08), value: micTestLevel)

                    Button(micTesting ? "Stop" : "Test Mic") {
                        if micTesting {
                            stopMicTest()
                        } else {
                            startMicTest()
                        }
                    }
                    .controlSize(.small)
                    .frame(width: 60)
                }
            }

            Section("Output Mode") {
                Picker("Mode", selection: $outputMode) {
                    Text("Clipboard Paste").tag(OutputMode.clipboardPaste.rawValue)
                    Text("Simulated Keystrokes").tag(OutputMode.simulatedKeystrokes.rawValue)
                    Text("Accessibility Insertion").tag(OutputMode.accessibilityInsertion.rawValue)
                }
                
                if outputMode == OutputMode.simulatedKeystrokes.rawValue {
                    Picker("Typing Speed", selection: $typingSpeed) {
                        ForEach(TypingSpeed.allCases, id: \.rawValue) { speed in
                            Text(speed.displayName).tag(speed.rawValue)
                        }
                    }
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

            Section("Dual Opinion") {
                Toggle("Run two Whisper models", isOn: $dualOpinionEnabled)
                if dualOpinionEnabled {
                    Picker("Second Model", selection: $secondWhisperModel) {
                        Text("Tiny").tag("tiny")
                        Text("Base").tag("base")
                        Text("Small").tag("small")
                        Text("Medium").tag("medium")
                        Text("Large").tag("large")
                    }
                    Picker("Merge", selection: $dualMergeMethod) {
                        Text("AI merge").tag("ai")
                        Text("Offline vote (no AI)").tag("vote")
                    }
                    Text(dualMergeMethod == "vote"
                         ? "Both models run in parallel; the better candidate is picked locally — no AI, fully offline."
                         : "Both models run in parallel, then an AI merges the results for better punctuation and accuracy.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("AI Polish") {
                Toggle("Enable AI Polish", isOn: $aiPolishEnabled)

                if aiPolishEnabled || (dualOpinionEnabled && dualMergeMethod == "ai") {
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

            Section("Menu Bar Icon") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(MenuBarIconStyle.allCases) { style in
                        Button {
                            menuBarIconStyle = style.rawValue
                        } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: style.previewImage())
                                    .frame(width: 32, height: 32)
                                Text(style.displayName)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(menuBarIconStyle == style.rawValue
                                          ? Color.accentColor.opacity(0.2)
                                          : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(menuBarIconStyle == style.rawValue
                                            ? Color.accentColor
                                            : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .formStyle(.grouped)
        }
        .frame(width: 480, height: 700)
        .padding()
        .onAppear {
            availableMicrophones = YOLOWhispApp.listInputDevices()
            hotkeys = StoredHotkey.decode(hotkeysJSON)
        }
        .onDisappear {
            stopMicTest()
        }
    }

    // MARK: - Mic Test

    private func startMicTest() {
        let engine = AudioCaptureEngine()
        if selectedMicrophoneID != 0 {
            engine.deviceID = AudioDeviceID(selectedMicrophoneID)
        }
        engine.audioLevelCallback = { level in
            micTestLevel = level
        }
        micTestEngine = engine
        engine.startCapture()
        micTesting = true
    }

    private func stopMicTest() {
        if let engine = micTestEngine {
            _ = engine.stopCapture()
            engine.audioLevelCallback = nil
            micTestEngine = nil
        }
        micTestLevel = 0.0
        micTesting = false
    }

    private func restartMicTest() {
        stopMicTest()
        startMicTest()
    }

}

// MARK: - Audio Level Meter

struct AudioLevelMeter: View {
    let level: Float
    private let barCount = 20

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index) / Float(barCount)
                // Scale level: raw RMS is typically 0.0–0.3 for speech, boost it
                let scaledLevel = min(level * 4.0, 1.0)
                let active = scaledLevel > threshold

                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(for: index, active: active))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.15))
        )
    }

    private func barColor(for index: Int, active: Bool) -> Color {
        guard active else { return Color.gray.opacity(0.15) }
        let ratio = Float(index) / Float(barCount)
        if ratio < 0.6 {
            return .green
        } else if ratio < 0.8 {
            return .yellow
        } else {
            return .red
        }
    }
}
