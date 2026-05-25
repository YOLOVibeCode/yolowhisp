import SwiftUI
import Cocoa
import CoreAudio

struct DiagnosticsView: View {
    // Hotkey config
    @AppStorage("hotkeys") private var hotkeysJSON: String = StoredHotkey.encode([StoredHotkey()])
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = 179
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = 0
    @AppStorage("selectedMicrophoneID") private var selectedMicrophoneID: Int = 0
    @AppStorage("whisperModel") private var whisperModel: String = "base"

    @State private var hotkeys: [StoredHotkey] = []
    private let recorder = HotkeyRecorderController()
    @State private var recordingId: UUID?

    // Key capture
    @State private var monitors: [Any] = []
    @State private var capturing = true
    @State private var lastKeyDisplay = ""
    @State private var lastKeyCode: UInt16 = 0
    @State private var lastModifiers: UInt = 0
    @State private var keyLog: [String] = []

    // Hotkey test
    @State private var hotkeyTestActive = false
    @State private var hotkeyDetected = false
    @State private var hotkeyDetectedName = ""
    @State private var resetWork: DispatchWorkItem?
    @State private var triggeredHotkeyId: UUID?

    // Mic test
    @State private var micTesting = false
    @State private var micLevel: Float = 0.0
    @State private var micEngine: AudioCaptureEngine?
    @State private var availableMics: [(id: AudioDeviceID, name: String)] = []

    // Dictation test
    @State private var dictating = false
    @State private var processing = false
    @State private var dictLevel: Float = 0.0
    @State private var dictEngine: AudioCaptureEngine?
    @State private var dictResult = ""
    @State private var dictTiming = ""

    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                tabButton("Hotkeys", icon: "keyboard", tab: 0)
                tabButton("Microphone", icon: "mic", tab: 1)
                tabButton("Dictation", icon: "text.bubble", tab: 2)
                tabButton("Key Log", icon: "list.bullet.rectangle", tab: 3)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)

            Divider().padding(.top, 4)

            // Content
            switch selectedTab {
            case 0: hotkeyTab
            case 1: microphoneTab
            case 2: dictationTab
            case 3: keyLogTab
            default: EmptyView()
            }
        }
        .frame(width: 520, height: 460)
        .onAppear {
            hotkeys = StoredHotkey.decode(hotkeysJSON)
            availableMics = YOLOWhispApp.listInputDevices()
            startCapture()
        }
        .onDisappear {
            stopCapture()
            stopMicTest()
            stopHotkeyTest()
        }
    }

    // MARK: - Tab Button

    private func tabButton(_ label: String, icon: String, tab: Int) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                Text(label)
                    .font(.caption2)
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

    // MARK: - Hotkeys Tab

    private var hotkeyTab: some View {
        VStack(spacing: 0) {
            // Big key display
            VStack(spacing: 4) {
                Text(lastKeyDisplay.isEmpty ? "Press any key" : lastKeyDisplay)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundColor(lastKeyDisplay.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                if lastKeyCode > 0 {
                    Text("code: \(lastKeyCode)  ·  mods: 0x\(String(lastModifiers, radix: 16))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 8)
            .background(Color(nsColor: .controlBackgroundColor))

            Divider()

            // Hotkey list
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(hotkeys.enumerated()), id: \.element.id) { index, hotkey in
                        let isTriggered = triggeredHotkeyId == hotkey.id
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isTriggered ? Color.green : Color.gray.opacity(0.2))
                                .frame(width: 8, height: 8)

                            Text(hotkey.displayName)
                                .font(.system(.body, design: .rounded))
                                .fontWeight(.medium)
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
                            .controlSize(.mini)
                            .disabled(lastKeyCode == 0)
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
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundColor(.red).font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.vertical, 5)
                    }

                    HStack {
                        Button {
                            hotkeys.append(StoredHotkey())
                            saveHotkeys()
                        } label: {
                            Label("Add Hotkey", systemImage: "plus.circle.fill").font(.caption)
                        }
                        .buttonStyle(.plain).foregroundColor(.accentColor)

                        Spacer()

                        Button {
                            if hotkeyTestActive { stopHotkeyTest() } else { startHotkeyTest() }
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(hotkeyDetected ? .green : (hotkeyTestActive ? .orange : Color.gray.opacity(0.3)))
                                    .frame(width: 7, height: 7)
                                Text(hotkeyDetected ? "Detected! (\(hotkeyDetectedName))" : (hotkeyTestActive ? "Listening..." : "Test Hotkeys"))
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(hotkeyDetected ? .green : (hotkeyTestActive ? .orange : .accentColor))
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

            // Mic picker
            Picker("Input Source", selection: $selectedMicrophoneID) {
                Text("System Default").tag(0)
                ForEach(availableMics, id: \.id) { mic in
                    Text(mic.name).tag(Int(mic.id))
                }
            }
            .padding(.horizontal, 20)
            .onChange(of: selectedMicrophoneID) { _, _ in
                if micTesting { stopMicTest(); startMicTest() }
            }

            // Level meter
            AudioLevelMeter(level: micLevel)
                .frame(height: 30)
                .padding(.horizontal, 20)
                .animation(.easeOut(duration: 0.08), value: micLevel)

            // Status
            if micTesting {
                Text("Speak to see the level meter respond")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Button(micTesting ? "Stop" : "Test Microphone") {
                if micTesting { stopMicTest() } else { startMicTest() }
            }

            Spacer()
        }
    }

    // MARK: - Dictation Tab

    private var dictationTab: some View {
        VStack(spacing: 12) {
            Spacer()

            if dictating {
                VStack(spacing: 8) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Image(systemName: "waveform")
                                .foregroundColor(.white)
                                .font(.title3)
                        )
                    Text("Recording...")
                        .font(.headline)
                        .foregroundColor(.red)

                    AudioLevelMeter(level: dictLevel)
                        .frame(height: 28)
                        .padding(.horizontal, 40)
                        .animation(.easeOut(duration: 0.08), value: dictLevel)

                    Button("Stop & Transcribe") { stopDictation() }
                        .controlSize(.large)
                }
            } else if processing {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Transcribing with \(whisperModel) model...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "mic.circle")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)

                    Button("Start Test Dictation") { startDictation() }
                        .controlSize(.large)

                    Text("Records audio, transcribes with Whisper, shows result")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Result
            if !dictResult.isEmpty && !dictating && !processing {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Result").font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(dictTiming).font(.caption2).foregroundColor(.secondary)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(dictResult, forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc").font(.caption2)
                        }.buttonStyle(.plain)
                    }
                    Text(dictResult)
                        .textSelection(.enabled)
                        .padding(10)
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
                Circle()
                    .fill(capturing ? .green : Color.gray.opacity(0.3))
                    .frame(width: 6, height: 6)
                Text(capturing ? "Capturing" : "Paused")
                    .font(.caption2).foregroundColor(.secondary)
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
                            Text(line)
                                .font(.system(size: 10.5, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 1.5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(i % 2 == 0 ? Color.clear : Color.gray.opacity(0.04))
                                .id(i)
                        }
                    }
                }
                .onChange(of: keyLog.count) { _, _ in
                    if let last = keyLog.indices.last { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Key Capture Engine

    private func startCapture() {
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

            // Update big display
            if event.type == .keyDown || (event.type == .flagsChanged && KeyCodeMap.isFlagsChangedKey(kc)) {
                lastKeyDisplay = KeyCodeMap.displayString(keyCode: kc, modifiers: di)
                if kc == KeyCodeMap.fnPhysicalKeyCode && (raw & NSEvent.ModifierFlags.function.rawValue) != 0 {
                    lastKeyCode = KeyCodeMap.globeKeyCode
                    lastModifiers = 0
                } else if KeyCodeMap.isFlagsChangedKey(kc) {
                    lastKeyCode = kc
                    lastModifiers = 0
                } else {
                    lastKeyCode = kc
                    lastModifiers = di
                }
            }

            // Check hotkey match (always, when on hotkey tab)
            if selectedTab == 0 { checkHotkeyMatch(event) }
        }
    }

    // MARK: - Hotkey Test

    private func startHotkeyTest() {
        hotkeyDetected = false
        hotkeyTestActive = true
    }

    private func stopHotkeyTest() {
        hotkeyTestActive = false
        hotkeyDetected = false
        resetWork?.cancel()
    }

    private func checkHotkeyMatch(_ event: NSEvent) {
        for hk in hotkeys {
            if matchesHotkey(event, hk) {
                hotkeyDetectedName = hk.displayName
                hotkeyDetected = true
                triggeredHotkeyId = hk.id
                resetWork?.cancel()
                let w = DispatchWorkItem {
                    hotkeyDetected = false
                    triggeredHotkeyId = nil
                }
                resetWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: w)
                return
            }
        }
    }

    private func matchesHotkey(_ event: NSEvent, _ hk: StoredHotkey) -> Bool {
        let kc = event.keyCode
        let di = event.modifierFlags.rawValue & NSEvent.ModifierFlags.deviceIndependentFlagsMask.rawValue
        if hk.keyCode == Int(KeyCodeMap.globeKeyCode) && KeyCodeMap.isGlobeKeyEvent(event) { return true }
        if event.type == .flagsChanged && KeyCodeMap.isFlagsChangedKey(kc) {
            return kc == UInt16(hk.keyCode) && hk.modifiers == 0
        }
        if event.type == .keyDown && kc == UInt16(hk.keyCode) && UInt(hk.modifiers) == di { return true }
        return false
    }

    // MARK: - Hotkey Storage

    private func saveHotkeys() {
        hotkeysJSON = StoredHotkey.encode(hotkeys)
        if let first = hotkeys.first {
            hotkeyKeyCode = first.keyCode
            hotkeyModifiers = first.modifiers
        }
    }

    // MARK: - Mic Test

    private func startMicTest() {
        let engine = AudioCaptureEngine()
        if selectedMicrophoneID != 0 { engine.deviceID = AudioDeviceID(selectedMicrophoneID) }
        engine.audioLevelCallback = { level in micLevel = level }
        micEngine = engine
        engine.startCapture()
        micTesting = true
    }

    private func stopMicTest() {
        if let e = micEngine { _ = e.stopCapture(); e.audioLevelCallback = nil; micEngine = nil }
        micLevel = 0; micTesting = false
    }

    // MARK: - Dictation Test

    private func startDictation() {
        dictResult = ""; dictTiming = ""; dictating = true
        let engine = AudioCaptureEngine()
        if selectedMicrophoneID != 0 { engine.deviceID = AudioDeviceID(selectedMicrophoneID) }
        engine.audioLevelCallback = { level in dictLevel = level }
        dictEngine = engine
        engine.startCapture()
    }

    private func stopDictation() {
        guard let engine = dictEngine else { return }
        dictating = false; processing = true; dictLevel = 0
        let data = engine.stopCapture()
        engine.audioLevelCallback = nil; dictEngine = nil

        if data.isEmpty {
            dictResult = "(No audio — check mic permissions)"; processing = false; return
        }
        let dur = Double(data.count) / (16000.0 * 2.0)

        Task {
            let start = Date()
            do {
                let mm = ModelManager()
                guard let model = mm.availableModels().first(where: { $0.name == whisperModel }) ?? mm.availableModels().first else {
                    await MainActor.run { dictResult = "(No model found)"; processing = false }; return
                }
                try mm.loadModel(model)
                let result = try await WhisperEngine(modelManager: mm).transcribe(audioData: data)
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run {
                    dictResult = result.text
                    dictTiming = String(format: "%.1fs audio → %.2fs (%@)", dur, elapsed, result.modelUsed)
                    processing = false
                }
            } catch {
                await MainActor.run { dictResult = "(Error: \(error.localizedDescription))"; processing = false }
            }
        }
    }
}
