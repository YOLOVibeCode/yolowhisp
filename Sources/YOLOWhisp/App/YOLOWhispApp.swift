import SwiftUI
import CoreAudio

@main
struct YOLOWhispApp: App {
    @AppStorage("selectedMicrophoneID") private var selectedMicrophoneID: Int = 0
    @AppStorage("menuBarIcon") private var menuBarIconStyle: String = MenuBarIconStyle.whisperBubble.rawValue
    @State private var availableMicrophones: [(id: AudioDeviceID, name: String)] = []

    private static let sharedAudioCapture = AudioCaptureEngine()
    private static let sharedModelManager = ModelManager()

    @StateObject private var controller: DictationController = {
        let audioCapture = sharedAudioCapture
        let modelManager = sharedModelManager
        let transcriber = WhisperEngine(modelManager: modelManager)
        let textOutputManager = TextOutputManager(outputs: [
            .clipboardPaste: ClipboardPaster(),
            .simulatedKeystrokes: KeystrokeTyper(),
            .accessibilityInsertion: AccessibilityInserter(),
        ])
        let historyStore = HistoryStore(databasePath: {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("YOLOWhisp")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir.appendingPathComponent("history.db").path
        }())
        let pill = PillViewController()

        return DictationController(
            audioCapture: audioCapture,
            transcriber: transcriber,
            textOutputManager: textOutputManager,
            historyStore: historyStore,
            pill: pill
        )
    }()

    private let hotkeyManager = HotkeyManager()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("outputMode") private var outputModeSetting: String = OutputMode.simulatedKeystrokes.rawValue
    @AppStorage("aiPolishEnabled") private var aiPolishEnabled: Bool = false
    @AppStorage("whisperModel") private var whisperModelName: String = "base"
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 179
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = 0
    @AppStorage("hotkeyTriggerMode") private var hotkeyTriggerMode: String = TriggerMode.hold.rawValue
    @AppStorage("hotkeys") private var hotkeysJSON: String = StoredHotkey.encode([StoredHotkey()])
    @AppStorage("dualOpinionEnabled") private var dualOpinionEnabled: Bool = false
    @AppStorage("secondWhisperModel") private var secondWhisperModel: String = "small"
    @AppStorage("aiProvider") private var aiProvider: String = ProviderType.ollama.rawValue
    @AppStorage("aiModelName") private var aiModelName: String = ""
    @AppStorage("aiApiKey") private var aiApiKey: String = ""
    @AppStorage("soundStyle") private var soundStyle: String = SoundFeedback.SoundStyle.tinkPop.rawValue

    private let updateChecker = GitHubUpdateChecker()

    private var historyStore: HistoryStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("YOLOWhisp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return HistoryStore(databasePath: dir.appendingPathComponent("history.db").path)
    }

    var body: some Scene {
        MenuBarExtra {
            Button(controller.isActive ? "Stop Dictation" : "Start Dictation") {
                if controller.isActive {
                    Task { await controller.stopDictation() }
                } else {
                    controller.startDictation()
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            .onAppear {
                controller.outputMode = OutputMode(rawValue: outputModeSetting) ?? .simulatedKeystrokes
                controller.postProcessEnabled = aiPolishEnabled
                SoundFeedback.shared.setStyle(SoundFeedback.SoundStyle(rawValue: soundStyle) ?? .tinkPop)
                loadWhisperModel()
                availableMicrophones = Self.listInputDevices()
                applyMicrophoneSelection()
                setupDualOpinion()
                setupHotkey()
            }
            Divider()
            Menu("Microphone") {
                let systemDefault = selectedMicrophoneID == 0
                Button {
                    selectedMicrophoneID = 0
                    applyMicrophoneSelection()
                } label: {
                    if systemDefault {
                        Text("✓ System Default")
                    } else {
                        Text("  System Default")
                    }
                }
                Divider()
                ForEach(availableMicrophones, id: \.id) { mic in
                    Button {
                        selectedMicrophoneID = Int(mic.id)
                        applyMicrophoneSelection()
                    } label: {
                        if Int(mic.id) == selectedMicrophoneID {
                            Text("✓ \(mic.name)")
                        } else {
                            Text("  \(mic.name)")
                        }
                    }
                }
            }
            Divider()
            Button("Diagnostics") {
                openDiagnosticsWindow()
            }
            Button("History") {
                openHistoryWindow()
            }
            Button("Settings...") {
                openSettingsWindow()
            }
            Button("Check for Updates...") {
                updateChecker.checkForUpdates()
            }
            .disabled(!updateChecker.canCheckForUpdates)
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            let style = MenuBarIconStyle(rawValue: menuBarIconStyle) ?? .whisperBubble
            Image(nsImage: style.menuBarImage())
        }

        .onChange(of: outputModeSetting) { _, newValue in
            controller.outputMode = OutputMode(rawValue: newValue) ?? .simulatedKeystrokes
        }
        .onChange(of: aiPolishEnabled) { _, newValue in
            controller.postProcessEnabled = newValue
        }
        .onChange(of: hotkeysJSON) { _, _ in setupHotkey() }
        .onChange(of: whisperModelName) { _, _ in loadWhisperModel() }
        .onChange(of: dualOpinionEnabled) { _, _ in setupDualOpinion() }
        .onChange(of: secondWhisperModel) { _, _ in setupDualOpinion() }
        .onChange(of: aiProvider) { _, _ in setupDualOpinion() }
        .onChange(of: aiModelName) { _, _ in setupDualOpinion() }

        Window("Onboarding", id: "onboarding") {
            OnboardingView(permissionChecker: PermissionManager())
        }
        .windowResizability(.contentSize)
    }

    private func setupHotkey() {
        hotkeyManager.unregisterAll()
        let storedHotkeys = StoredHotkey.decode(hotkeysJSON)

        for hotkey in storedHotkeys {
            let config = hotkey.config
            let mode = TriggerMode(rawValue: hotkey.triggerMode) ?? .hold

            if mode == .hold {
                hotkeyManager.register(
                    hotkey: config,
                    onKeyDown: { [controller] in controller.startDictation() },
                    onKeyUp: { [controller] in Task { await controller.stopDictation() } }
                )
            } else {
                hotkeyManager.register(hotkey: config) { [controller] in
                    if controller.isActive {
                        Task { await controller.stopDictation() }
                    } else {
                        controller.startDictation()
                    }
                }
            }
        }
    }

    private func loadWhisperModel() {
        let models = Self.sharedModelManager.availableModels()
        if let model = models.first(where: { $0.name == whisperModelName }) {
            try? Self.sharedModelManager.loadModel(model)
        } else if let first = models.first {
            try? Self.sharedModelManager.loadModel(first)
        }
    }

    private func setupDualOpinion() {
        guard dualOpinionEnabled else {
            controller.secondTranscriber = nil
            controller.dualOpinionPolisher = nil
            return
        }

        // Set up second whisper engine with a different model
        let secondModelManager = ModelManager()
        let models = secondModelManager.availableModels()
        if let model = models.first(where: { $0.name == secondWhisperModel }) {
            try? secondModelManager.loadModel(model)
            controller.secondTranscriber = WhisperEngine(modelManager: secondModelManager)
        }

        // Set up the polisher with the configured AI provider
        let providerType = ProviderType(rawValue: aiProvider) ?? .ollama
        let endpoint: String
        switch providerType {
        case .ollama: endpoint = "http://localhost:11434/api/generate"
        case .openai: endpoint = "https://api.openai.com/v1/chat/completions"
        case .anthropic: endpoint = "https://api.anthropic.com/v1/messages"
        case .custom: endpoint = ""
        }

        let polishConfig = PostProcessorConfig(
            providerType: providerType,
            modelName: aiModelName.isEmpty ? "llama3.2" : aiModelName,
            endpoint: endpoint,
            apiKey: aiApiKey.isEmpty ? nil : aiApiKey
        )
        controller.dualOpinionPolisher = DualOpinionPolisher(config: polishConfig)
    }

    private func applyMicrophoneSelection() {
        Self.sharedAudioCapture.deviceID = selectedMicrophoneID == 0 ? nil : AudioDeviceID(selectedMicrophoneID)
    }

    static func listInputDevices() -> [(id: AudioDeviceID, name: String)] {
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize
        ) == noErr else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress, 0, nil, &dataSize, &deviceIDs
        ) == noErr else { return [] }

        var inputDevices: [(id: AudioDeviceID, name: String)] = []
        for id in deviceIDs {
            // Check if device has input streams
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else { continue }

            // Get device name
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var nameRef: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameRef) == noErr,
                  let cfName = nameRef?.takeUnretainedValue() else { continue }
            inputDevices.append((id: id, name: cfName as String))
        }
        return inputDevices
    }

    private func openDiagnosticsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "YOLOWhisp Diagnostics"
        window.contentView = NSHostingView(rootView: DiagnosticsView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettingsWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "YOLOWhisp Settings"
        window.contentView = NSHostingView(rootView: SettingsView())
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openHistoryWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Dictation History"
        window.contentView = NSHostingView(rootView: HistoryView(store: historyStore))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
