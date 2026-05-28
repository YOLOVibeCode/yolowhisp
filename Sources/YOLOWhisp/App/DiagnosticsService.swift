import Foundation

public enum CheckStatus: String {
    case ok, warn, fail, running, pending, skipped
}

public enum DiagnosticStage: String, CaseIterable, Identifiable {
    case micPermission, accessibilityPermission, whisperCLI, modelLoaded,
         inputDevice, liveAudio, endToEnd, outputMode, aiProvider
    public var id: String { rawValue }

    var title: String {
        switch self {
        case .micPermission:          return "Microphone permission"
        case .accessibilityPermission: return "Accessibility permission"
        case .whisperCLI:             return "whisper-cli installed"
        case .modelLoaded:            return "Whisper model loaded"
        case .inputDevice:            return "Input device"
        case .liveAudio:              return "Live audio (speak now)"
        case .endToEnd:               return "End-to-end transcription"
        case .outputMode:             return "Text output"
        case .aiProvider:             return "AI provider"
        }
    }
}

/// A one-click fix the Diagnostics UI can offer for a failing stage.
public enum FixKind: Equatable {
    case openAccessibility, requestMic, downloadModel, installWhisper
}

public struct CheckResult: Identifiable {
    public let id: DiagnosticStage
    public var status: CheckStatus
    public var detail: String
    public var remediation: String?
    public var fix: FixKind? = nil
}

/// Runs each pipeline stage against the REAL app components and reports a
/// structured pass/warn/fail with remediation. UI-free and testable.
@MainActor
final class DiagnosticsService: ObservableObject {
    @Published var results: [DiagnosticStage: CheckResult] = [:]
    @Published var isRunning = false

    private let services: AppServices
    init(services: AppServices) { self.services = services }

    /// Failing/warning stages that offer a one-click fix, in the order
    /// "Set up everything" should run them (permissions → whisper-cli → model).
    func fixableStages() -> [(stage: DiagnosticStage, fix: FixKind)] {
        let order: [FixKind] = [.requestMic, .openAccessibility, .installWhisper, .downloadModel]
        var out: [(DiagnosticStage, FixKind)] = []
        for kind in order {
            for stage in DiagnosticStage.allCases {
                if let r = results[stage], r.fix == kind, r.status == .fail || r.status == .warn {
                    out.append((stage, kind))
                }
            }
        }
        return out
    }

    func runAll() async {
        isRunning = true
        for stage in DiagnosticStage.allCases {
            results[stage] = CheckResult(id: stage, status: .running, detail: "…", remediation: nil)
            results[stage] = await run(stage)
        }
        isRunning = false
    }

    func run(_ stage: DiagnosticStage) async -> CheckResult {
        switch stage {
        case .micPermission:          return checkMicPermission()
        case .accessibilityPermission: return checkAccessibility()
        case .whisperCLI:             return checkWhisperCLI()
        case .modelLoaded:            return checkModel()
        case .inputDevice:            return checkInputDevice()
        case .liveAudio:              return await checkLiveAudio()
        case .endToEnd:               return await checkEndToEnd()
        case .outputMode:             return checkOutputMode()
        case .aiProvider:             return await checkAIProvider()
        }
    }

    // MARK: - Stage checks

    private func checkMicPermission() -> CheckResult {
        let ok = services.permissions.checkMicrophonePermission()
        return CheckResult(id: .micPermission, status: ok ? .ok : .fail,
                           detail: ok ? "Granted" : "Not granted",
                           remediation: ok ? nil : "System Settings → Privacy & Security → Microphone → enable YOLOWhisp",
                           fix: ok ? nil : .requestMic)
    }

    private func checkAccessibility() -> CheckResult {
        let ok = services.permissions.checkAccessibilityPermission()
        // Needed for global hotkeys and keystroke/accessibility output.
        return CheckResult(id: .accessibilityPermission, status: ok ? .ok : .fail,
                           detail: ok ? "Granted" : "Not granted",
                           remediation: ok ? nil : "System Settings → Privacy & Security → Accessibility → enable YOLOWhisp",
                           fix: ok ? nil : .openAccessibility)
    }

    private func checkWhisperCLI() -> CheckResult {
        let path = services.whisperPath
        let ok = FileManager.default.fileExists(atPath: path)
        return CheckResult(id: .whisperCLI, status: ok ? .ok : .fail,
                           detail: ok ? path : "Not found at \(path)",
                           remediation: ok ? nil : "brew install whisper-cpp",
                           fix: ok ? nil : .installWhisper)
    }

    private func checkModel() -> CheckResult {
        let models = services.modelManager.availableModels()
        guard let current = services.modelManager.currentModel else {
            let detail = models.isEmpty ? "No models found" : "None loaded (\(models.count) available)"
            return CheckResult(id: .modelLoaded, status: .fail, detail: detail,
                               remediation: "Download a Whisper model (base ≈ 147MB)",
                               fix: .downloadModel)
        }
        let exists = FileManager.default.fileExists(atPath: current.path)
        return CheckResult(id: .modelLoaded, status: exists ? .ok : .fail,
                           detail: exists ? "\(current.name) (+\(models.count - 1) more)" : "\(current.name) file missing",
                           remediation: exists ? nil : "Re-download the model")
    }

    private func checkInputDevice() -> CheckResult {
        guard let device = services.audioCapture.currentInputDevice() else {
            return CheckResult(id: .inputDevice, status: .fail, detail: "No input device",
                               remediation: "Connect a microphone / set a default input in Sound settings")
        }
        return CheckResult(id: .inputDevice, status: .ok, detail: "\(device.name) [\(device.id)]", remediation: nil)
    }

    private func checkLiveAudio() async -> CheckResult {
        guard !services.controller.isActive else {
            return CheckResult(id: .liveAudio, status: .skipped, detail: "Dictation in progress", remediation: nil)
        }
        guard services.permissions.checkMicrophonePermission() else {
            return CheckResult(id: .liveAudio, status: .skipped, detail: "Mic permission required", remediation: nil)
        }
        let engine = services.audioCapture
        let prior = engine.audioLevelCallback
        let box = PeakBox()
        engine.audioLevelCallback = { level in box.peak = max(box.peak, level) }
        engine.startCapture()
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        _ = engine.stopCapture()
        engine.audioLevelCallback = prior
        let peak = box.peak
        if peak < 0.005 {
            return CheckResult(id: .liveAudio, status: .warn,
                               detail: "Silent (peak \(String(format: "%.3f", peak)))",
                               remediation: "Speak during the check; check mic gain / mute / phantom power")
        }
        return CheckResult(id: .liveAudio, status: .ok, detail: "Signal detected (peak \(String(format: "%.3f", peak)))", remediation: nil)
    }

    private func checkEndToEnd() async -> CheckResult {
        guard let pcm = services.sampleProvider(), !pcm.isEmpty else {
            return CheckResult(id: .endToEnd, status: .skipped, detail: "No bundled sample audio", remediation: nil)
        }
        guard services.modelManager.currentModel != nil else {
            return CheckResult(id: .endToEnd, status: .skipped, detail: "No model loaded", remediation: "Load a model first")
        }
        let sink = CapturingTextOutput()
        let controller = DictationController(
            audioCapture: FileAudioCapture(pcm: pcm),
            transcriber: WhisperEngine(whisperPath: services.whisperPath, modelManager: services.modelManager),
            textOutputManager: TextOutputManager(outputs: [sink.mode: sink]),
            historyStore: HistoryStore(),
            pill: NullPillDisplay()
        )
        controller.outputMode = sink.mode
        // Mute the start/stop chirps for the silent self-test.
        let priorStyle = SoundFeedback.shared.currentStyle
        SoundFeedback.shared.setStyle(.none)
        controller.startDictation()
        await controller.stopDictation()
        SoundFeedback.shared.setStyle(priorStyle)
        let text = sink.captured.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            return CheckResult(id: .endToEnd, status: .fail,
                               detail: controller.lastRunInfo?.error ?? "No text produced",
                               remediation: "Check whisper-cli + model; see Logs")
        }
        return CheckResult(id: .endToEnd, status: .ok, detail: "“\(text.prefix(90))”", remediation: nil)
    }

    private func checkOutputMode() -> CheckResult {
        let mode = services.controller.outputMode
        let needsAX = (mode == .simulatedKeystrokes || mode == .accessibilityInsertion || mode == .clipboardPaste)
        let axOK = services.permissions.checkAccessibilityPermission()
        if needsAX && !axOK {
            return CheckResult(id: .outputMode, status: .warn, detail: "\(label(mode)) — needs Accessibility",
                               remediation: "Grant Accessibility so output can be inserted",
                               fix: .openAccessibility)
        }
        return CheckResult(id: .outputMode, status: .ok, detail: label(mode), remediation: nil)
    }

    private func checkAIProvider() async -> CheckResult {
        guard let config = services.aiConfigProvider() else {
            return CheckResult(id: .aiProvider, status: .skipped, detail: "AI polish off", remediation: nil)
        }
        do {
            let provider = ProviderFactory.make(config: config)
            let reply = try await provider.process(text: "ping")
            return CheckResult(id: .aiProvider, status: .ok,
                               detail: "\(config.providerType.rawValue): \(config.modelName) reachable (\(reply.prefix(20))…)",
                               remediation: nil)
        } catch {
            return CheckResult(id: .aiProvider, status: .warn,
                               detail: "\(config.providerType.rawValue): \(error)",
                               remediation: "Check the provider is running / API key / endpoint")
        }
    }

    private func label(_ mode: OutputMode) -> String {
        switch mode {
        case .clipboardPaste:        return "Clipboard paste"
        case .simulatedKeystrokes:   return "Simulated keystrokes"
        case .accessibilityInsertion: return "Accessibility insertion"
        case .clipboardOnly:         return "Clipboard only"
        }
    }
}

/// Reference box so the audio callback (delivered on main) can record a peak
/// the @MainActor check reads after sampling.
private final class PeakBox { var peak: Float = 0 }
