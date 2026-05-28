import SwiftUI
import Cocoa

/// The pipeline health check + one-click fixes. Shared by the Diagnostics
/// window (technical framing) and the first-run Setup window (friendly framing).
struct HealthCheckView: View {
    let services: AppServices
    var friendly: Bool = false

    @StateObject private var diag: DiagnosticsService
    @State private var busyStage: DiagnosticStage?
    @State private var downloadProgress: Double = 0
    @State private var fixNote: String?
    @State private var ranOnce = false
    @State private var settingUpAll = false

    init(services: AppServices, friendly: Bool = false) {
        self.services = services
        self.friendly = friendly
        _diag = StateObject(wrappedValue: DiagnosticsService(services: services))
    }

    private var busy: Bool { diag.isRunning || busyStage != nil || settingUpAll }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(friendly ? "Setup" : "Pipeline Health").font(.headline)
                Spacer()
                Button {
                    Task { settingUpAll = true; await setUpEverything(); settingUpAll = false }
                } label: {
                    HStack(spacing: 5) {
                        if settingUpAll { ProgressView().controlSize(.small) }
                        Text("Set up everything")
                    }
                }
                .disabled(busy)
                Button("Re-check") { Task { await diag.runAll() } }
                    .disabled(busy)
            }
            .padding(12)

            if let note = fixNote {
                Text(note).font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.bottom, 6)
            }

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(DiagnosticStage.allCases) { stage in
                        row(stage)
                        Divider()
                    }
                }
            }
        }
        .onAppear {
            if !ranOnce { ranOnce = true; Task { await diag.runAll() } }
        }
    }

    private func row(_ stage: DiagnosticStage) -> some View {
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
            if busyStage == stage {
                if result?.fix == .downloadModel {
                    ProgressView(value: downloadProgress).frame(width: 64)
                } else {
                    ProgressView().controlSize(.small)
                }
            } else if let fix = result?.fix {
                Button(fixLabel(fix)) { Task { await runFix(stage, fix) } }
                    .controlSize(.small).disabled(busy)
            }
            Button {
                Task { diag.results[stage] = await diag.run(stage) }
            } label: { Image(systemName: "arrow.clockwise").font(.caption2) }
            .buttonStyle(.plain).foregroundColor(.secondary).disabled(busy)
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

    private func fixLabel(_ kind: FixKind) -> String {
        switch kind {
        case .openAccessibility: return "Open Settings"
        case .requestMic:        return "Grant"
        case .downloadModel:     return "Download base"
        case .installWhisper:    return "Install"
        }
    }

    private func setUpEverything() async {
        if diag.results.isEmpty { await diag.runAll() }
        for (stage, kind) in diag.fixableStages() {
            await runFix(stage, kind)
        }
        await diag.runAll()
    }

    private func runFix(_ stage: DiagnosticStage, _ kind: FixKind) async {
        fixNote = nil
        switch kind {
        case .requestMic:
            _ = await services.permissions.requestMicrophonePermission()
        case .openAccessibility:
            services.permissions.openAccessibilitySettings()
            fixNote = "Toggle YOLOWhisp on in Accessibility, then re-check."
        case .downloadModel:
            busyStage = stage; downloadProgress = 0
            do {
                let downloader = ModelDownloader()
                _ = try await downloader.download(model: "base") { p in
                    Task { @MainActor in downloadProgress = p }
                }
                let models = services.modelManager.availableModels()
                if let m = models.first(where: { $0.name == "base" }) ?? models.first {
                    try? services.modelManager.loadModel(m)
                }
                fixNote = "Downloaded base model."
            } catch {
                AppLog.error("Model download failed: \(error)")
                fixNote = "Download failed — see Logs."
            }
            busyStage = nil
        case .installWhisper:
            let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            guard let brew = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("brew install whisper-cpp", forType: .string)
                fixNote = "Homebrew not found — copied “brew install whisper-cpp” to clipboard."
                return
            }
            busyStage = stage
            let exit = await Task.detached { () -> Int32 in
                let runner = ProcessRunner(timeout: 600)
                return (try? runner.run(executablePath: brew, arguments: ["install", "whisper-cpp"]))?.exitCode ?? -1
            }.value
            AppLog.info("brew install whisper-cpp exit \(exit)")
            fixNote = exit == 0 ? "Installed whisper-cpp." : "Install failed — run “brew install whisper-cpp” manually."
            busyStage = nil
        }
        diag.results[stage] = await diag.run(stage)
        if kind == .downloadModel || kind == .installWhisper {
            diag.results[.endToEnd] = await diag.run(.endToEnd)
        }
    }
}
