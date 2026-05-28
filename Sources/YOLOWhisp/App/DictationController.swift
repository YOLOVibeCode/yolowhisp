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
    public var frontmostAppProvider: () -> String? = { NSWorkspace.shared.frontmostApplication?.localizedName }

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
        let targetApp = frontmostAppProvider()
        let audioData = audioCapture.stopCapture()
        let audioBytes = audioData.count
        let started = Date()
        SoundFeedback.shared.playStop()
        pill.setState(.processing)

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

            // Optional enhancement: dual-opinion merge (AI), offline consensus
            // vote, or single-pass polish. These must NEVER drop the dictation —
            // if the optional step fails (e.g. AI provider 404), fall back to the
            // raw transcription and record the error, but still output + save.
            if let polisher = dualOpinionPolisher, candidates.count > 1 {
                do {
                    let merged = try await polisher.merge(candidates: candidates.map(\.text))
                    processedText = merged
                    finalText = merged
                } catch {
                    runError = "merge failed (using primary): \(error)"
                    AppLog.error(runError!)
                }
            } else if let strategy = consensusStrategy, candidates.count > 1 {
                // Offline: pick the best candidate, no LLM involved.
                finalText = strategy.selectBest(from: candidates).text
            } else if postProcessEnabled, let processor = postProcessor {
                do {
                    let processed = try await processor.process(text: primaryResult.text)
                    processedText = processed
                    finalText = processed
                } catch {
                    runError = "AI polish failed (using raw transcription): \(error)"
                    AppLog.error(runError!)
                }
            }

            try await textOutputManager.output(text: finalText, mode: outputMode)

            let entry = HistoryEntry(
                rawText: rawText,
                processedText: processedText,
                duration: primaryResult.duration,
                modelUsed: modelsUsed,
                targetApp: targetApp
            )
            try historyStore.save(entry: entry)
        } catch {
            runError = "\(error)"
            AppLog.error("Dictation pipeline failed: \(error)")
        }

        lastRunInfo = LastRunInfo(
            timestamp: Date(),
            rawText: rawText,
            finalText: finalText,
            modelsUsed: modelsUsed,
            duration: Date().timeIntervalSince(started),
            audioBytes: audioBytes,
            outputMode: outputMode,
            error: runError
        )
        pill.setState(.idle)
        isActive = false
    }
}
