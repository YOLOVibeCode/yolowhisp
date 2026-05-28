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
    private let windowStore = AppWindowStore()

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @AppStorage("outputMode") private var outputModeSetting: String = OutputMode.simulatedKeystrokes.rawValue
    @AppStorage("aiPolishEnabled") private var aiPolishEnabled: Bool = false
    @AppStorage("whisperModel") private var whisperModelName: String = "base"
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 179
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = 0
    @AppStorage("hotkeyTriggerMode") private var hotkeyTriggerMode: String = TriggerMode.hold.rawValue
    @AppStorage("hotkeys") private var hotkeysJSON: String = StoredHotkey.encode([StoredHotkey()])
    @AppStorage("dualOpinionEnabled") private var dualOpinionEnabled: Bool = false
    @AppStorage("dualMergeMethod") private var dualMergeMethod: String = "ai"
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
                AppLog.installCrashHandlers()
                AppLog.info("YOLOWhisp launched")
                controller.outputMode = OutputMode(rawValue: outputModeSetting) ?? .simulatedKeystrokes
                controller.postProcessEnabled = aiPolishEnabled
                SoundFeedback.shared.setStyle(SoundFeedback.SoundStyle(rawValue: soundStyle) ?? .tinkPop)
                loadWhisperModel()
                availableMicrophones = Self.listInputDevices()
                applyMicrophoneSelection()
                setupDualOpinion()
                setupPostProcessor()
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
                // Recompute on each open so newly-connected devices appear.
                ForEach(Self.listInputDevices(), id: \.id) { mic in
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
            setupPostProcessor()
        }
        .onChange(of: hotkeysJSON) { _, _ in setupHotkey() }
        .onChange(of: whisperModelName) { _, _ in loadWhisperModel() }
        .onChange(of: dualOpinionEnabled) { _, _ in setupDualOpinion() }
        .onChange(of: dualMergeMethod) { _, _ in setupDualOpinion() }
        .onChange(of: secondWhisperModel) { _, _ in setupDualOpinion() }
        .onChange(of: aiProvider) { _, _ in setupDualOpinion(); setupPostProcessor() }
        .onChange(of: aiModelName) { _, _ in setupDualOpinion(); setupPostProcessor() }
        .onChange(of: aiApiKey) { _, _ in setupDualOpinion(); setupPostProcessor() }

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
            controller.consensusStrategy = nil
            return
        }

        // Set up second whisper engine with a different model
        let secondModelManager = ModelManager()
        let models = secondModelManager.availableModels()
        if let model = models.first(where: { $0.name == secondWhisperModel }) {
            try? secondModelManager.loadModel(model)
            controller.secondTranscriber = WhisperEngine(modelManager: secondModelManager)
        }

        // Choose how the two candidates get merged.
        if dualMergeMethod == "vote" {
            // Offline majority vote — no LLM, fully local.
            controller.dualOpinionPolisher = nil
            controller.consensusStrategy = MajorityVoteConsensus()
        } else {
            // AI merge via the configured provider.
            controller.consensusStrategy = nil
            controller.dualOpinionPolisher = DualOpinionPolisher(config: aiProviderConfig())
        }
    }

    /// Inject (or clear) the single-pass AI Polish provider on the controller.
    /// Without this, toggling "AI Polish" flips a flag the controller can't act
    /// on because it has no provider to call.
    private func setupPostProcessor() {
        guard aiPolishEnabled else {
            controller.postProcessor = nil
            return
        }
        let config = aiProviderConfig(customPrompt: DualOpinionPolisher.singlePolishPrompt)
        controller.postProcessor = ProviderFactory.make(config: config)
    }

    /// Build a provider config from the current AI settings.
    private func aiProviderConfig(customPrompt: String? = nil) -> PostProcessorConfig {
        let providerType = ProviderType(rawValue: aiProvider) ?? .ollama
        let endpoint: String
        switch providerType {
        case .ollama: endpoint = "http://localhost:11434/api/generate"
        case .openai: endpoint = "https://api.openai.com/v1/chat/completions"
        case .anthropic: endpoint = "https://api.anthropic.com/v1/messages"
        case .custom: endpoint = ""
        }
        return PostProcessorConfig(
            providerType: providerType,
            modelName: aiModelName.isEmpty ? "llama3.2" : aiModelName,
            endpoint: endpoint,
            apiKey: aiApiKey.isEmpty ? nil : aiApiKey,
            customPrompt: customPrompt
        )
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

    /// Bundle the REAL shared components so Diagnostics observes/exercises them.
    private func makeServices() -> AppServices {
        AppServices(
            controller: controller,
            audioCapture: Self.sharedAudioCapture,
            modelManager: Self.sharedModelManager,
            hotkeyManager: hotkeyManager,
            aiConfigProvider: { Self.currentAIConfig() }
        )
    }

    /// Current AI provider config when polish/dual-AI is enabled, else nil.
    static func currentAIConfig() -> PostProcessorConfig? {
        let d = UserDefaults.standard
        let polish = d.bool(forKey: "aiPolishEnabled")
        let dual = d.bool(forKey: "dualOpinionEnabled")
        let method = d.string(forKey: "dualMergeMethod") ?? "ai"
        guard polish || (dual && method == "ai") else { return nil }
        let providerType = ProviderType(rawValue: d.string(forKey: "aiProvider") ?? "ollama") ?? .ollama
        let endpoint: String
        switch providerType {
        case .ollama: endpoint = "http://localhost:11434/api/generate"
        case .openai: endpoint = "https://api.openai.com/v1/chat/completions"
        case .anthropic: endpoint = "https://api.anthropic.com/v1/messages"
        case .custom: endpoint = ""
        }
        let model = d.string(forKey: "aiModelName") ?? ""
        let key = d.string(forKey: "aiApiKey") ?? ""
        return PostProcessorConfig(
            providerType: providerType,
            modelName: model.isEmpty ? "llama3.2" : model,
            endpoint: endpoint,
            apiKey: key.isEmpty ? nil : key,
            customPrompt: DualOpinionPolisher.singlePolishPrompt
        )
    }

    private func openDiagnosticsWindow() {
        let services = makeServices()
        windowStore.show(.diagnostics, title: "YOLOWhisp Diagnostics",
                         size: NSSize(width: 560, height: 480), resizable: true) {
            NSHostingView(rootView: DiagnosticsView(services: services))
        }
    }

    private func openSettingsWindow() {
        windowStore.show(.settings, title: "YOLOWhisp Settings",
                         size: NSSize(width: 450, height: 500), resizable: false) {
            NSHostingView(rootView: SettingsView(openDiagnostics: { openDiagnosticsWindow() }))
        }
    }

    private func openHistoryWindow() {
        windowStore.show(.history, title: "Dictation History",
                         size: NSSize(width: 500, height: 400), resizable: true) {
            NSHostingView(rootView: HistoryView(store: historyStore))
        }
    }
}

/// Retains and reuses the app's auxiliary windows. Creating an NSWindow as a
/// local with the default `isReleasedWhenClosed = true` caused an over-release
/// crash (EXC_BAD_ACCESS in _NSWindowTransformAnimation dealloc) when the
/// window closed. Here windows are kept alive, not released on close, and
/// reused so repeated menu clicks don't stack duplicates.
final class AppWindowStore {
    enum Kind { case diagnostics, settings, history }
    private var windows: [Kind: NSWindow] = [:]

    func show(_ kind: Kind, title: String, size: NSSize, resizable: Bool, makeContent: () -> NSView) {
        if let existing = windows[kind] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        var style: NSWindow.StyleMask = [.titled, .closable]
        if resizable { style.insert(.resizable) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false   // ARC owns it; avoids the double-free on close
        window.title = title
        window.contentView = makeContent()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[kind] = window
    }
}
