import AppKit
import Foundation

public final class DictationController: ObservableObject {
    private let audioCapture: any AudioCapturing
    private let transcriber: any Transcribing
    private let textOutputManager: TextOutputManager
    private let historyStore: any HistoryStoring
    private let postProcessor: (any PostProcessing)?
    private let pill: any PillDisplaying

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
        pill.setState(.recording)
        audioCapture.startCapture()
    }

    public func stopDictation() async {
        guard isActive else { return }
        let targetApp = frontmostAppProvider()
        let audioData = audioCapture.stopCapture()
        pill.setState(.processing)

        do {
            let result = try await transcriber.transcribe(audioData: audioData)
            var finalText = result.text
            var processedText: String? = nil

            if postProcessEnabled, let processor = postProcessor {
                let processed = try await processor.process(text: result.text)
                processedText = processed
                finalText = processed
            }

            try await textOutputManager.output(text: finalText, mode: outputMode)

            let entry = HistoryEntry(
                rawText: result.text,
                processedText: processedText,
                duration: result.duration,
                modelUsed: result.modelUsed,
                targetApp: targetApp
            )
            try historyStore.save(entry: entry)
        } catch {
            // Log error
        }

        pill.setState(.idle)
        isActive = false
    }
}
