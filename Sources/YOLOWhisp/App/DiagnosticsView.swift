import SwiftUI
import Cocoa
import CoreAudio

struct DiagnosticsView: View {
    let services: AppServices
    @StateObject private var diag: DiagnosticsService
    @ObservedObject private var controller: DictationController

    @AppStorage("hotkeys") private var hotkeysJSON: String = StoredHotkey.encode([StoredHotkey()])
    @AppStorage("selectedMicrophoneID") private var selectedMicrophoneID: Int = 0

    @State private var hotkeys: [StoredHotkey] = []
    private let recorder = HotkeyRecorderController()
    @State private var recordingId: UUID?

    // Key capture (raw NSEvent dev aid)
    @State private var monitors: [Any] = []
    @State private var capturing = false
    @State private var lastKeyDisplay = ""
    @State private var lastKeyCode: UInt16 = 0
    @State private var lastModifiers: UInt = 0
    @State private var keyLog: [String] = []

    // Hotkey live-test (driven by the REAL HotkeyManager.onTrigger)
    @State private var triggeredHotkeyId: UUID?
    @State private var lastTriggerName = ""
    @State private var resetWork: DispatchWorkItem?
    @State private var priorOnTrigger: ((HotkeyConfig, Bool) -> Void)?

    // Mic test (uses the REAL shared engine)
    @State private var micTesting = false
    @State private var micLevel: Float = 0.0
    @State private var availableMics: [(id: AudioDeviceID, name: String)] = []
    @State private var priorLevelCallback: ((Float) -> Void)?

    // Dictation test (real engine + model, capturing sink — no typing)
    @State private var dictating = false
    @State private var processing = false
    @State private var dictLevel: Float = 0.0
    @State private var dictEngine: AudioCaptureEngine?
    @State private var dictResult = ""
    @State private var dictTiming = ""

    @State private var selectedTab = 0

    // Logs
    @State private var logText = ""

    init(services: AppServices) {
        self.services = services
        _diag = StateObject(wrappedValue: DiagnosticsService(services: services))
        _controller = ObservedObject(wrappedValue: services.controller)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tabButton("Health", icon: "stethoscope", tab: 0)
                tabButton("Hotkeys", icon: "keyboard", tab: 1)
                tabButton("Microphone", icon: "mic", tab: 2)
                tabButton("Dictation", icon: "text.bubble", tab: 3)
                tabButton("Key Log", icon: "list.bullet.rectangle", tab: 4)
                tabButton("Logs", icon: "doc.text.magnifyingglass", tab: 5)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider().padding(.top, 4)

            switch selectedTab {
            case 0: healthTab
            case 1: hotkeyTab
            case 2: microphoneTab
            case 3: dictationTab
            case 4: keyLogTab
            case 5: logsTab
            default: EmptyView()
            }
        }
        .frame(width: 560, height: 480)
        .onAppear {
            // Reset transient state so a reopened window starts clean.
            hotkeys = StoredHotkey.decode(hotkeysJSON)
            availableMics = YOLOWhispApp.listInputDevices()
            triggeredHotkeyId = nil
            lastTriggerName = ""
            micLevel = 0; dictLevel = 0
            dictResult = ""; dictTiming = ""
            dictating = false; processing = false
            installHotkeyObserver()
            startCapture()
        }
        .onDisappear {
            stopCapture()
            stopMicTest()
            teardownDictation()
            removeHotkeyObserver()
        }
    }

    private func tabButton(_ label: String, icon: String, tab: Int) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 14))
                Text(label).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
            )
            .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Health Check Tab

    private var healthTab: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pipeline Health").font(.headline)
                Spacer()
                Button {
                    Task { await diag.runAll() }
                } label: {
                    HStack(spacing: 5) {
                        if diag.isRunning { ProgressView().controlSize(.small) }
                        Text(diag.isRunning ? "Running…" : "Run Health Check")
                    }
                }
                .disabled(diag.isRunning)
            }
            .padding(12)

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(DiagnosticStage.allCases) { stage in
                        healthRow(stage)
                        Divider()
                    }
                }
            }
        }
    }

    private func healthRow(_ stage: DiagnosticStage) -> some View {
        let result = diag.results[stage]
        let status = result?.status ?? .pending
        return HStack(alignment: .top, spacing: 10) {
            statusIcon(status).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(stage.title).font(.system(.body, design: .rounded)).fontWeight(.medium)
                if let detail = result?.detail, !detail.isEmpty, detail != "…" {
                    Text(detail).font(.caption).foregroundColor(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if let fix = result?.remediation {
                    Text(fix).font(.caption2).foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            Button {
                Task { diag.results[stage] = await diag.run(stage) }
            } label: {
                Image(systemName: "arrow.clockwise").font(.caption2)
            }
            .buttonStyle(.plain).foregroundColor(.secondary)
            .disabled(diag.isRunning)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    @ViewBuilder
    private func statusIcon(_ status: CheckStatus) -> some View {
        switch status {
        case .ok:      Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
        case .warn:    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
        case .fail:    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
        case .running: ProgressView().controlSize(.small)
        case .skipped: Image(systemName: "minus.circle").foregroundColor(.secondary)
        case .pending: Image(systemName: "circle").foregroundColor(.secondary.opacity(0.4))
        }
    }

    // MARK: - Logs Tab

    private var logsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Application Log").font(.headline)
                Spacer()
                Button("Refresh") { logText = AppLog.recentLines() }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([AppLog.fileURL])
                }
            }
            ScrollView {
                Text(logText.isEmpty ? "No log entries yet." : logText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .padding(6)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(6)
            Text(AppLog.fileURL.path).font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
        }
        .padding(12)
        .onAppear { logText = AppLog.recentLines() }
    }

    // MARK: - Hotkeys Tab

    private var hotkeyTab: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Text(lastKeyDisplay.isEmpty ? "Press any key" : lastKeyDisplay)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(lastKeyDisplay.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity).padding(.top, 12)
                if lastKeyCode > 0 {
                    Text("code: \(lastKeyCode)  ·  mods: 0x\(String(lastModifiers, radix: 16))")
                        .font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(hotkeys.enumerated()), id: \.element.id) { index, hotkey in
                        let isTriggered = triggeredHotkeyId == hotkey.id
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isTriggered ? Color.green : Color.gray.opacity(0.2))
                                .frame(width: 8, height: 8)
                            Text(hotkey.displayName)
                                .font(.system(.body, design: .rounded)).fontWeight(.medium)
                                .foregroundColor(isTriggered ? .green : .primary)
                                .frame(minWidth: 80, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { hotkey.triggerMode },
                                set: { hotkeys[index].triggerMode = $0; saveHotkeys() }
                            )) {
                                Text("Hold").tag("hold")
                                Text("Toggle").tag("toggle")
                            }
                            .frame(width: 85)
                            Spacer()
                            Button("← Set") {
                                guard lastKeyCode > 0 else { return }
                                hotkeys[index].keyCode = Int(lastKeyCode)
                                hotkeys[index].modifiers = Int(lastModifiers)
                                saveHotkeys()
                            }
                            .controlSize(.mini).disabled(lastKeyCode == 0)
                            .help("Set to the last key pressed above")
                            Button(recordingId == hotkey.id ? "Press..." : "Record") {
                                recordingId = hotkey.id
                                recorder.startRecording { config in
                                    if let idx = hotkeys.firstIndex(where: { $0.id == hotkey.id }) {
                                        hotkeys[idx].keyCode = Int(config.keyCode)
                                        hotkeys[idx].modifiers = Int(config.modifiers)
                                        saveHotkeys()
                                    }
                                    recordingId = nil
                                }
                            }
                            .controlSize(.mini)
                            if hotkeys.count > 1 {
                                Button {
                                    hotkeys.removeAll { $0.id == hotkey.id }
                                    saveHotkeys()
                                } label: {
                                    Image(systemName: "minus.circle.fill").foregroundColor(.red).font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                    }

                    HStack {
                        Button {
                            hotkeys.append(StoredHotkey()); saveHotkeys()
                        } label: {
                            Label("Add Hotkey", systemImage: "plus.circle.fill").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundColor(.accentColor)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(triggeredHotkeyId != nil ? .green : Color.gray.opacity(0.3))
                                .frame(width: 7, height: 7)
                            Text(triggeredHotkeyId != nil ? "Fired: \(lastTriggerName)" : "Press a registered hotkey to test")
                                .font(.caption).foregroundColor(triggeredHotkeyId != nil ? .green : .secondary)
                        }
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                }
            }
            Spacer()
        }
    }

    // MARK: - Microphone Tab

    private var microphoneTab: some View {
        VStack(spacing: 16) {
            Spacer()
            Picker("Input Source", selection: $selectedMicrophoneID) {
                Text("System Default").tag(0)
                ForEach(availableMics, id: \.id) { mic in
                    Text(mic.name).tag(Int(mic.id))
                }
            }
            .padding(.horizontal, 20)
            .onChange(of: selectedMicrophoneID) { _, newValue in
                // Apply to the REAL shared engine so it matches what dictation uses.
                services.audioCapture.deviceID = newValue == 0 ? nil : AudioDeviceID(newValue)
                if micTesting { stopMicTest(); startMicTest() }
            }

            if let dev = services.audioCapture.currentInputDevice() {
                Text("Engine device: \(dev.name)").font(.caption2).foregroundColor(.secondary)
            }

            AudioLevelMeter(level: micLevel)
                .frame(height: 30).padding(.horizontal, 20)
                .animation(.easeOut(duration: 0.08), value: micLevel)

            if micTesting {
                Text("Speak to see the level meter respond").font(.caption).foregroundColor(.secondary)
            }

            Button(micTesting ? "Stop" : "Test Microphone") {
                if micTesting { stopMicTest() } else { startMicTest() }
            }
            .disabled(controller.isActive)
            Spacer()
        }
    }

    // MARK: - Dictation Tab

    private var dictationTab: some View {
        VStack(spacing: 12) {
            Spacer()
            if dictating {
                VStack(spacing: 8) {
                    Circle().fill(Color.red).frame(width: 40, height: 40)
                        .overlay(Image(systemName: "waveform").foregroundColor(.white).font(.title3))
                    Text("Recording...").font(.headline).foregroundColor(.red)
                    AudioLevelMeter(level: dictLevel)
                        .frame(height: 28).padding(.horizontal, 40)
                        .animation(.easeOut(duration: 0.08), value: dictLevel)
                    Button("Stop & Transcribe") { stopDictationTest() }.controlSize(.large)
                }
            } else if processing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Transcribing with \(services.modelManager.currentModel?.name ?? "?")…")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle").font(.system(size: 40)).foregroundColor(.secondary)
                    Button("Start Test Dictation") { startDictationTest() }
                        .controlSize(.large).disabled(controller.isActive)
                    Text("Records via the real mic, transcribes with the loaded model (does not type).")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
            }

            if !dictResult.isEmpty && !dictating && !processing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Result").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(dictTiming).font(.caption2).foregroundColor(.secondary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dictResult, forType: .string)
                        } label: { Image(systemName: "doc.on.doc").font(.caption2) }.buttonStyle(.plain)
                    }
                    Text(dictResult).textSelection(.enabled).padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                }
                .padding(.horizontal, 20)
            }
            Spacer()
        }
    }

    // MARK: - Key Log Tab

    private var keyLogTab: some View {
        VStack(spacing: 0) {
            HStack {
                Circle().fill(capturing ? .green : Color.gray.opacity(0.3)).frame(width: 6, height: 6)
                Text(capturing ? "Capturing" : "Paused").font(.caption2).foregroundColor(.secondary)
                Spacer()
                Button("Clear") { keyLog.removeAll() }.controlSize(.mini).disabled(keyLog.isEmpty)
                Button(capturing ? "Pause" : "Resume") {
                    if capturing { stopCapture() } else { startCapture() }
                }.controlSize(.mini)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(keyLog.enumerated()), id: \.offset) { i, line in
                            Text(line).font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled).padding(.horizontal, 8).padding(.vertical, 1.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(i % 2 == 0 ? Color.clear : Color.gray.opacity(0.04)).id(i)
                        }
                    }
                }
                .onChange(of: keyLog.count) { _, _ in
                    if let last = keyLog.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Key Capture (raw NSEvent dev aid)

    private func startCapture() {
        guard monitors.isEmpty else { return }
        capturing = true
        let types: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged, .systemDefined]
        let g = NSEvent.addGlobalMonitorForEvents(matching: types) { e in handleKeyEvent(e, "global") }
        let l = NSEvent.addLocalMonitorForEvents(matching: types) { e in handleKeyEvent(e, "local"); return e }
        monitors = [g as Any, l as Any]
    }

    private func stopCapture() {
        for m in monitors { NSEvent.removeMonitor(m) }
        monitors.removeAll()
        capturing = false
    }

    private func handleKeyEvent(_ event: NSEvent, _ source: String) {
        let kc = event.keyCode
        let raw = event.modifierFlags.rawValue
        let di = raw & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue

        let typeName: String
        switch event.type {
        case .keyDown: typeName = "KEY↓"
        case .keyUp: typeName = "KEY↑"
        case .flagsChanged: typeName = "FLAG"
        case .systemDefined: typeName = "SYS "
        default: typeName = "?   "
        }

        let keyName = KeyCodeMap.name(for: kc)
        var flags: [String] = []
        if di & NSEvent.ModifierFlags.capsLock.rawValue != 0 { flags.append("caps") }
        if di & NSEvent.ModifierFlags.shift.rawValue != 0 { flags.append("⇧") }
        if di & NSEvent.ModifierFlags.control.rawValue != 0 { flags.append("⌃") }
        if di & NSEvent.ModifierFlags.option.rawValue != 0 { flags.append("⌥") }
        if di & NSEvent.ModifierFlags.command.rawValue != 0 { flags.append("⌘") }
        if raw & NSEvent.ModifierFlags.function.rawValue != 0 { flags.append("fn") }

        let line = "\(source) \(typeName)  code=\(kc)  \"\(keyName)\"  [\(flags.isEmpty ? "—" : flags.joined(separator: " "))]"

        DispatchQueue.main.async {
            keyLog.append(line)
            if keyLog.count > 300 { keyLog.removeFirst() }
            if event.type == .keyDown || (event.type == .flagsChanged && KeyCodeMap.isFlagsChangedKey(kc)) {
                lastKeyDisplay = KeyCodeMap.displayString(keyCode: kc, modifiers: di)
                if kc == KeyCodeMap.fnPhysicalKeyCode && (raw & NSEvent.ModifierFlags.function.rawValue) != 0 {
                    lastKeyCode = KeyCodeMap.globeKeyCode; lastModifiers = 0
                } else if KeyCodeMap.isFlagsChangedKey(kc) {
                    lastKeyCode = kc; lastModifiers = 0
                } else {
                    lastKeyCode = kc; lastModifiers = di
                }
            }
        }
    }

    // MARK: - Hotkey live-test (observes the REAL HotkeyManager)

    private func installHotkeyObserver() {
        priorOnTrigger = services.hotkeyManager.onTrigger
        services.hotkeyManager.onTrigger = { config, isKeyDown in
            guard isKeyDown else { return }
            let match = hotkeys.first { $0.keyCode == Int(config.keyCode) && $0.modifiers == Int(config.modifiers) }
            triggeredHotkeyId = match?.id
            lastTriggerName = match?.displayName ?? KeyCodeMap.displayString(keyCode: config.keyCode, modifiers: config.modifiers)
            resetWork?.cancel()
            let w = DispatchWorkItem { triggeredHotkeyId = nil }
            resetWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
        }
    }

    private func removeHotkeyObserver() {
        services.hotkeyManager.onTrigger = priorOnTrigger
        priorOnTrigger = nil
        resetWork?.cancel()
    }

    // MARK: - Hotkey Storage

    private func saveHotkeys() {
        hotkeysJSON = StoredHotkey.encode(hotkeys)
    }

    // MARK: - Mic Test (REAL shared engine)

    private func startMicTest() {
        guard !controller.isActive else { return }
        let engine = services.audioCapture
        priorLevelCallback = engine.audioLevelCallback
        engine.deviceID = selectedMicrophoneID == 0 ? nil : AudioDeviceID(selectedMicrophoneID)
        engine.audioLevelCallback = { level in micLevel = level }
        engine.startCapture()
        micTesting = true
    }

    private func stopMicTest() {
        guard micTesting else { return }
        _ = services.audioCapture.stopCapture()
        services.audioCapture.audioLevelCallback = priorLevelCallback
        priorLevelCallback = nil
        micLevel = 0
        micTesting = false
    }

    // MARK: - Dictation Test (real mic + model, capturing sink — no typing)

    private func startDictationTest() {
        guard !controller.isActive else { return }
        dictResult = ""; dictTiming = ""; dictating = true
        let engine = services.audioCapture
        engine.deviceID = selectedMicrophoneID == 0 ? nil : AudioDeviceID(selectedMicrophoneID)
        engine.audioLevelCallback = { level in dictLevel = level }
        dictEngine = engine
        engine.startCapture()
    }

    private func stopDictationTest() {
        guard let engine = dictEngine else { return }
        dictating = false; processing = true; dictLevel = 0
        let data = engine.stopCapture()
        engine.audioLevelCallback = nil; dictEngine = nil

        if data.isEmpty {
            dictResult = "(No audio captured — see Health Check / Logs)"; processing = false; return
        }
        let dur = Double(data.count) / (16000.0 * 2.0)

        Task {
            let start = Date()
            do {
                guard services.modelManager.currentModel != nil else {
                    await MainActor.run { dictResult = "(No model loaded)"; processing = false }; return
                }
                let engine = WhisperEngine(whisperPath: services.whisperPath, modelManager: services.modelManager)
                let result = try await engine.transcribe(audioData: data)
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run {
                    dictResult = result.text.isEmpty ? "(empty transcription)" : result.text
                    dictTiming = String(format: "%.1fs audio → %.2fs (%@)", dur, elapsed, result.modelUsed)
                    processing = false
                }
            } catch {
                await MainActor.run { dictResult = "(Error: \(error))"; processing = false }
            }
        }
    }

    private func teardownDictation() {
        if let engine = dictEngine {
            _ = engine.stopCapture()
            engine.audioLevelCallback = nil
            dictEngine = nil
        }
        dictating = false
    }
}
