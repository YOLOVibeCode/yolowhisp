import Foundation
@testable import YOLOWhisp

// MARK: - Sample + manifest

/// One benchmark item: an audio identifier (relative path) and the exact text
/// that was spoken (ground truth).
struct BenchmarkSample: Equatable {
    let id: String
    let reference: String
}

/// Parses the tab-separated manifest produced by `gen-benchmark-samples.sh`.
/// Each line is `<relative-audio-path>\t<reference text>`. Blank and malformed
/// lines are skipped. Pure and side-effect free so it is trivially testable.
enum BenchmarkManifest {
    static func parse(_ tsv: String) -> [BenchmarkSample] {
        var samples: [BenchmarkSample] = []
        for rawLine in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let id = parts[0].trimmingCharacters(in: .whitespaces)
            let reference = String(parts[1])
            guard !id.isEmpty, !reference.isEmpty else { continue }
            samples.append(BenchmarkSample(id: id, reference: reference))
        }
        return samples
    }
}

// MARK: - Scores

/// Accuracy scores for a single (reference, hypothesis) pair.
struct BenchmarkScores: Equatable {
    let wer: Double
    /// WER after number normalization (digits vs spelled-out) — closer to a
    /// "did it get the meaning right" score, ignoring cosmetic formatting.
    let semanticWER: Double
    let cer: Double
    let punctuationF1: Double

    /// Clamped word-level accuracy in [0, 1].
    var wordAccuracy: Double { max(0, 1 - wer) }
    var semanticWordAccuracy: Double { max(0, 1 - semanticWER) }

    static func score(reference: String, hypothesis: String) -> BenchmarkScores {
        BenchmarkScores(
            wer: AccuracyMetrics.wordErrorRate(reference: reference, hypothesis: hypothesis),
            semanticWER: AccuracyMetrics.semanticWordErrorRate(reference: reference, hypothesis: hypothesis),
            cer: AccuracyMetrics.characterErrorRate(reference: reference, hypothesis: hypothesis),
            punctuationF1: AccuracyMetrics.punctuationScore(reference: reference, hypothesis: hypothesis).f1
        )
    }
}

// MARK: - Run result

/// Outcome of transcribing (and optionally AI-polishing) one sample with one
/// model/prompt configuration.
struct BenchmarkRunResult {
    let model: String
    let promptMode: String
    let sampleID: String
    let reference: String

    let rawHypothesis: String
    let rawScores: BenchmarkScores
    let audioSeconds: Double
    let processingSeconds: Double

    // AI Polish stage (only populated when a polisher is supplied).
    let polishedHypothesis: String?
    let polishedScores: BenchmarkScores?
    let polishError: String?

    var didPolish: Bool { polishedScores != nil }
}

// MARK: - Config

/// A model/prompt configuration to evaluate. The transcriber is injected so the
/// runner has no dependency on whisper-cli — tests pass a mock.
struct BenchmarkConfig {
    let model: String
    let promptMode: String
    let transcriber: any Transcribing
}

// MARK: - Runner

/// Orchestrates the benchmark: for every configuration and sample, transcribe,
/// score, then (optionally, as the final stage) AI-polish and re-score.
///
/// Everything external is injected (`loadAudio`, transcribers, `polisher`) so
/// the orchestration can be unit-tested without audio files, whisper-cli, or a
/// live AI provider.
struct BenchmarkRunner {
    let samples: [BenchmarkSample]
    let configs: [BenchmarkConfig]
    /// Resolves a sample to raw 16 kHz mono PCM plus its duration in seconds.
    let loadAudio: (BenchmarkSample) throws -> (pcm: Data, seconds: Double)
    /// Optional final-stage AI polisher applied to every raw transcription.
    let polisher: (any PostProcessing)?
    /// Optional progress hook, called as each result is produced.
    var onResult: ((BenchmarkRunResult) -> Void)?

    init(
        samples: [BenchmarkSample],
        configs: [BenchmarkConfig],
        loadAudio: @escaping (BenchmarkSample) throws -> (pcm: Data, seconds: Double),
        polisher: (any PostProcessing)? = nil,
        onResult: ((BenchmarkRunResult) -> Void)? = nil
    ) {
        self.samples = samples
        self.configs = configs
        self.loadAudio = loadAudio
        self.polisher = polisher
        self.onResult = onResult
    }

    func run() async throws -> [BenchmarkRunResult] {
        // Decode each sample's audio once and reuse it across configurations.
        var audioCache: [String: (pcm: Data, seconds: Double)] = [:]
        var results: [BenchmarkRunResult] = []

        for config in configs {
            for sample in samples {
                let audio: (pcm: Data, seconds: Double)
                if let cached = audioCache[sample.id] {
                    audio = cached
                } else {
                    audio = try loadAudio(sample)
                    audioCache[sample.id] = audio
                }
                guard !audio.pcm.isEmpty else { continue }

                let transcription = try await config.transcriber.transcribe(audioData: audio.pcm)
                let raw = transcription.text
                let rawScores = BenchmarkScores.score(reference: sample.reference, hypothesis: raw)

                // Final stage: AI polish (optional). Never fail the run if the
                // provider errors — record the error and keep the raw result.
                var polishedHypothesis: String?
                var polishedScores: BenchmarkScores?
                var polishError: String?
                if let polisher {
                    do {
                        let polished = try await polisher.process(text: raw)
                        polishedHypothesis = polished
                        polishedScores = BenchmarkScores.score(reference: sample.reference, hypothesis: polished)
                    } catch {
                        polishError = "\(error)"
                    }
                }

                let result = BenchmarkRunResult(
                    model: config.model,
                    promptMode: config.promptMode,
                    sampleID: sample.id,
                    reference: sample.reference,
                    rawHypothesis: raw,
                    rawScores: rawScores,
                    audioSeconds: audio.seconds,
                    processingSeconds: transcription.duration,
                    polishedHypothesis: polishedHypothesis,
                    polishedScores: polishedScores,
                    polishError: polishError
                )
                results.append(result)
                onResult?(result)
            }
        }
        return results
    }
}
