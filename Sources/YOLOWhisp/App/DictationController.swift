import AppKit
import Foundation

public final class DictationController: ObservableObject {
    private let audioCapture: any AudioCapturing
    private let transcriber: any Transcribing
    private let textOutputManager: TextOutputManager
    private let historyStore: any HistoryStoring
    private let pill: any PillDisplaying

    /// Optional single-pass LLM polisher applied when AI Polish is enabled
    /// (and dual-opinion is not active). Settable so the app can swap it as
    /// provider settings change.
    public var postProcessor: (any PostProcessing)?

    /// Optional second transcriber for "dual opinion" mode.
    /// When set, both transcribers run in parallel and results are merged by the polisher.
    public var secondTranscriber: (any Transcribing)?

    /// Optional dual opinion polisher — merges two transcription candidates via LLM.
    public var dualOpinionPolisher: (any CandidateMerging)?

    /// Optional offline merge strategy — picks the best of multiple candidates
    /// without an LLM. Used for dual-model mode when AI merge isn't selected.
    public var consensusStrategy: (any ConsensusStrategy)?

    @Published public private(set) var isActive: Bool = false

    /// Summary of the most recent dictation run, for the Diagnostics view to
    /// show what the REAL pipeline last produced (or why it failed).
    public struct LastRunInfo {
        public let timestamp: Date
        public let rawText: String
        public let finalText: String
        public let modelsUsed: String
        public let duration: TimeInterval
        public let audioBytes: Int
        public let outputMode: OutputMode
        public let error: String?
    }
    @Published public private(set) var lastRunInfo: LastRunInfo?

    public var outputMode: OutputMode = .simulatedKeystrokes
    public var postProcessEnabled: Bool = false
    public var autoSwitchRemoteTyping: Bool = true
    public var frontmostAppProvider: () -> String? = { NSWorkspace.shared.frontmostApplication?.localizedName }
    public var frontmostBundleIdProvider: () -> String? = { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }

    public init(
        audioCapture: any AudioCapturing,
        transcriber: any Transcribing,
        textOutputManager: TextOutputManager,
        historyStore: any HistoryStoring,
        postProcessor: (any PostProcessing)? = nil,
        pill: any PillDisplaying
    ) {
        self.audioCapture = audioCapture
        self.transcriber = transcriber
        self.textOutputManager = textOutputManager
        self.historyStore = historyStore
        self.postProcessor = postProcessor
        self.pill = pill
    }

    public func startDictation() {
        guard !isActive else { return }
        isActive = true
        SoundFeedback.shared.playStart()
        pill.setState(.recording)
        audioCapture.startCapture()
    }

    public func stopDictation() async {
        guard isActive else { return }
        // Capture frontmost-app info and update UI on the main thread. NSWorkspace
        // and the pill (NSPanel/NSHostingView) are not safe to touch off-main, and
        // this method runs on Swift's cooperative pool (via `Task { await ... }`).
        let (targetApp, bundleId): (String?, String?) = await MainActor.run {
            (frontmostAppProvider(), frontmostBundleIdProvider())
        }
        let audioData = audioCapture.stopCapture()
        let audioBytes = audioData.count
        let started = Date()
        SoundFeedback.shared.playStop()
        await MainActor.run { pill.setState(.processing) }

        var rawText = ""
        var finalText = ""
        var modelsUsed = ""
        var runError: String?

        do {
            // Run transcription — dual model if second transcriber is set
            var candidates: [TranscriptionResult] = []

            if let second = secondTranscriber {
                // Run both in parallel
                async let r1 = transcriber.transcribe(audioData: audioData)
                async let r2 = second.transcribe(audioData: audioData)
                let (result1, result2) = try await (r1, r2)
                candidates = [result1, result2]
            } else {
                let result = try await transcriber.transcribe(audioData: audioData)
                candidates = [result]
            }

            let primaryResult = candidates[0]
            finalText = primaryResult.text
            rawText = candidates.map(\.text).joined(separator: " | ")
            modelsUsed = candidates.map(\.modelUsed).joined(separator: "+")
            var processedText: String? = nil

            // Guard: if nothing intelligible was transcribed (silence / too
            // short), do NOT run AI polish, type, or save. Feeding empty text to
            // a polish provider makes the model echo its own system prompt,
            // which would then be typed out — the cause of garbage output.
            let hasText = !primaryResult.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            // Optional enhancement: dual-opinion merge (AI), offline consensus
            // vote, or single-pass polish. These must NEVER drop the dictation —
            // if the optional step fails (e.g. AI provider 404), fall back to the
            // raw transcription and record the error, but still output + save.
            if hasText, let polisher = dualOpinionPolisher, candidates.count > 1 {
                do {
                    let merged = try await polisher.merge(candidates: candidates.map(\.text))
                    processedText = merged
                    finalText = merged
                } catch {
                    runError = "merge failed (using primary): \(error)"
                    AppLog.error(runError!)
                }
            } else if hasText, let strategy = consensusStrategy, candidates.count > 1 {
                // Offline: pick the best candidate, no LLM involved.
                finalText = strategy.selectBest(from: candidates).text
            } else if hasText, postProcessEnabled, let processor = postProcessor {
                do {
                    let processed = try await processor.process(text: primaryResult.text)
                    // Defend against a provider that echoes its instructions
                    // instead of returning polished text: keep the raw text.
                    let trimmed = processed.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty {
                        runError = "AI polish returned empty (using raw transcription)"
                        AppLog.error(runError!)
                    } else {
                        processedText = processed
                        finalText = processed
                    }
                } catch {
                    runError = "AI polish failed (using raw transcription): \(error)"
                    AppLog.error(runError!)
                }
            }

            // Only type and persist when there is actual content.
            if hasText {
                // Auto-detect RDP/VM clients and route to key-code emulation + Ctrl+V paste fallback.
                let effectiveMode: OutputMode
                if autoSwitchRemoteTyping {
                    let isRemote = RemoteSessionDetector.isRemote(bundleId: bundleId, name: targetApp)
                    
                    if isRemote {
                        // Remote session detected: prefer key-code typing if text is fully mappable,
                        // otherwise fall back to Ctrl+V clipboard paste.
                        if KeystrokeTyper.isFullyMappable(finalText) {
                            effectiveMode = .remoteKeystrokes
                        } else {
                            // Unmappable characters → clipboard paste with Ctrl+V for Windows
                            effectiveMode = .remoteClipboardPaste
                        }
                    } else {
                        // Local macOS app: use the user's chosen mode.
                        effectiveMode = outputMode
                    }
                } else {
                    // Auto-switch disabled: always use user's chosen mode.
                    effectiveMode = outputMode
                }
                
                try await textOutputManager.output(text: finalText, mode: effectiveMode)

                let entry = HistoryEntry(
                    rawText: rawText,
                    processedText: processedText,
                    duration: primaryResult.duration,
                    modelUsed: modelsUsed,
                    targetApp: targetApp
                )
                try historyStore.save(entry: entry)
            } else {
                AppLog.info("Empty transcription — skipping output and save")
            }
        } catch {
            runError = "\(error)"
            AppLog.error("Dictation pipeline failed: \(error)")
        }

        let info = LastRunInfo(
            timestamp: Date(),
            rawText: rawText,
            finalText: finalText,
            modelsUsed: modelsUsed,
            duration: Date().timeIntervalSince(started),
            audioBytes: audioBytes,
            outputMode: outputMode,
            error: runError
        )
        // Publish state and update the pill on the main thread (see note above).
        await MainActor.run {
            self.lastRunInfo = info
            self.pill.setState(.idle)
            self.isActive = false
        }
    }
}
