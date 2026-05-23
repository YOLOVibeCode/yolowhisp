import SwiftUI

@main
struct YOLOWhispApp: App {
    @StateObject private var controller: DictationController = {
        let audioCapture = AudioCaptureEngine()
        let modelManager = ModelManager()
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

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    private var historyStore: HistoryStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("YOLOWhisp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return HistoryStore(databasePath: dir.appendingPathComponent("history.db").path)
    }

    var body: some Scene {
        MenuBarExtra("YOLOWhisp", systemImage: "waveform") {
            Button(controller.isActive ? "Stop Dictation" : "Start Dictation") {
                if controller.isActive {
                    Task { await controller.stopDictation() }
                } else {
                    controller.startDictation()
                }
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Button("History") {
                openHistoryWindow()
            }
            Button("Settings...") {
                openSettingsWindow()
            }
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Window("Onboarding", id: "onboarding") {
            OnboardingView()
        }
        .windowResizability(.contentSize)
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
