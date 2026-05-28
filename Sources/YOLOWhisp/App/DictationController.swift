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
    public var dualOpinionPolisher: DualOpinionPolisher?

    /// Optional offline merge strategy — picks the best of multiple candidates
    /// without an LLM. Used for dual-model mode when AI merge isn't selected.
    public var consensusStrategy: (any ConsensusStrategy)?

    @Published public private(set) var isActive: Bool = false
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
        SoundFeedback.shared.playStop()
        pill.setState(.processing)

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
            var finalText = primaryResult.text
            var processedText: String? = nil
            let modelsUsed = candidates.map(\.modelUsed).joined(separator: "+")

            // Dual opinion merge (AI), offline consensus vote, or single polish
            if let polisher = dualOpinionPolisher, candidates.count > 1 {
                let merged = try await polisher.merge(candidates: candidates.map(\.text))
                processedText = merged
                finalText = merged
            } else if let strategy = consensusStrategy, candidates.count > 1 {
                // Offline: pick the best candidate, no LLM involved.
                finalText = strategy.selectBest(from: candidates).text
            } else if postProcessEnabled, let processor = postProcessor {
                let processed = try await processor.process(text: primaryResult.text)
                processedText = processed
                finalText = processed
            }

            try await textOutputManager.output(text: finalText, mode: outputMode)

            let entry = HistoryEntry(
                rawText: candidates.map(\.text).joined(separator: " | "),
                processedText: processedText,
                duration: primaryResult.duration,
                modelUsed: modelsUsed,
                targetApp: targetApp
            )
            try historyStore.save(entry: entry)
        } catch {
            AppLog.error("Dictation pipeline failed: \(error)")
        }

        pill.setState(.idle)
        isActive = false
    }
}
