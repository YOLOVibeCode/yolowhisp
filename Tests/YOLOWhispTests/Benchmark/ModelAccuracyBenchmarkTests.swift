import XCTest
import Foundation
@testable import YOLOWhisp

/// End-to-end transcription accuracy benchmark.
///
/// This is a thin orchestration layer: it resolves files, builds real
/// `WhisperEngine`s (and, optionally, a real AI-polish provider), then delegates
/// the actual work to the testable components `BenchmarkRunner` and
/// `BenchmarkReport`. A ranked summary is written to `benchmark-results.md` at
/// the repo root.
///
/// Not part of the normal test run (needs whisper-cli + model files, slow):
///
///   scripts/gen-benchmark-samples.sh
///   RUN_WHISPER_BENCHMARK=1 swift test --filter ModelAccuracyBenchmarkTests
///
/// To also run the final AI Polish stage (needs a reachable provider, defaults
/// to local Ollama):
///
///   RUN_WHISPER_BENCHMARK=1 WHISPER_BENCHMARK_POLISH=1 \
///     swift test --filter ModelAccuracyBenchmarkTests
///
final class ModelAccuracyBenchmarkTests: XCTestCase {

    func testModelAccuracyBenchmark() async throws {
        guard ProcessInfo.processInfo.environment["RUN_WHISPER_BENCHMARK"] != nil else {
            throw XCTSkip("Set RUN_WHISPER_BENCHMARK=1 to run the model accuracy benchmark.")
        }

        let benchDir = Self.benchmarkDirectory()
        let manifestURL = benchDir.appendingPathComponent("manifest.tsv")
        guard let manifestText = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            throw XCTSkip("No manifest at \(manifestURL.path). Run scripts/gen-benchmark-samples.sh first.")
        }

        let samples = BenchmarkManifest.parse(manifestText)
        guard !samples.isEmpty else { throw XCTSkip("Manifest is empty: \(manifestURL.path)") }

        let whisperPath = WhisperEngine.resolvedWhisperPath
        guard FileManager.default.fileExists(atPath: whisperPath) else {
            throw XCTSkip("whisper-cli not found at \(whisperPath)")
        }

        var models = ModelManager().availableModels().sorted { $0.size < $1.size }
        // Optional filter: WHISPER_BENCHMARK_MODELS=base,large-v3-turbo narrows
        // the run (useful for fast polish-prompt iteration).
        if let filter = ProcessInfo.processInfo.environment["WHISPER_BENCHMARK_MODELS"] {
            let wanted = Set(filter.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            models = models.filter { wanted.contains($0.name) }
        }
        guard !models.isEmpty else { throw XCTSkip("No Whisper models installed (or none matched the filter).") }

        // Build one configuration per (model x prompt mode).
        let punctuationPrompt = "Hello, how are you? I'm doing great! That's wonderful. Let's meet at 3:30 PM. Don't forget — it's urgent!"
        let promptModes: [(name: String, prompt: String?)] = [
            ("no-prompt", nil),
            ("punct-prompt", punctuationPrompt),
        ]

        var configs: [BenchmarkConfig] = []
        for model in models {
            for mode in promptModes {
                let manager = ModelManager()
                try manager.loadModel(model)
                let engine = WhisperEngine(whisperPath: whisperPath, modelManager: manager)
                engine.initialPrompt = mode.prompt
                configs.append(BenchmarkConfig(model: model.name, promptMode: mode.name, transcriber: engine))
            }
        }

        // Optional final stage: a real AI polish provider, configured from env.
        let polisher = Self.makePolisherIfEnabled()

        print("\n=== YOLOWhisp Model Accuracy Benchmark ===")
        print("Samples: \(samples.count) | Models: \(models.map(\.name).joined(separator: ", "))")
        print("Prompt modes: \(promptModes.map(\.name).joined(separator: ", "))")
        print("AI Polish: \(polisher.map { "on (\($0.providerName))" } ?? "off")\n")

        let runner = BenchmarkRunner(
            samples: samples,
            configs: configs,
            loadAudio: { sample in
                let url = benchDir.appendingPathComponent(sample.id)
                let loaded = try BenchmarkAudioLoader.loadPCM16kMono(url: url)
                return (pcm: loaded.pcm, seconds: loaded.durationSeconds)
            },
            polisher: polisher,
            onResult: { r in
                print(String(format: "  %@/%@  %@  WER %.1f%%  punctF1 %.2f%@",
                             r.model, r.promptMode, r.sampleID,
                             r.rawScores.wer * 100, r.rawScores.punctuationF1,
                             r.polishedScores.map { String(format: "  -> polished WER %.1f%%", $0.wer * 100) } ?? ""))
            }
        )

        let results = try await runner.run()
        guard !results.isEmpty else { throw XCTSkip("No results produced (no loadable samples).") }

        let report = BenchmarkReport.markdown(results: results, sampleCount: samples.count)
        print("\n" + report)

        let resultsURL = Self.packageRoot().appendingPathComponent("benchmark-results.md")
        try? report.write(to: resultsURL, atomically: true, encoding: .utf8)
        print("Full report written to \(resultsURL.path)")

        XCTAssertFalse(results.isEmpty)
    }

    // MARK: - AI Polish provider

    /// Build a real polish provider when WHISPER_BENCHMARK_POLISH is set.
    /// Provider/model/endpoint/key come from env vars, defaulting to local Ollama.
    private static func makePolisherIfEnabled() -> (any PostProcessing)? {
        let env = ProcessInfo.processInfo.environment
        guard env["WHISPER_BENCHMARK_POLISH"] != nil else { return nil }

        let providerType = ProviderType(rawValue: env["WHISPER_POLISH_PROVIDER"] ?? "ollama") ?? .ollama
        let defaultEndpoint: String
        switch providerType {
        case .ollama:    defaultEndpoint = "http://localhost:11434/api/generate"
        case .openai:    defaultEndpoint = "https://api.openai.com/v1/chat/completions"
        case .anthropic: defaultEndpoint = "https://api.anthropic.com/v1/messages"
        case .custom:    defaultEndpoint = ""
        }
        let config = PostProcessorConfig(
            providerType: providerType,
            modelName: env["WHISPER_POLISH_MODEL"] ?? "llama3.2",
            endpoint: env["WHISPER_POLISH_ENDPOINT"] ?? defaultEndpoint,
            apiKey: env["WHISPER_POLISH_API_KEY"],
            customPrompt: polishPrompt(from: env)
        )
        return ProviderFactory.make(config: config)
    }

    /// Select the polish system prompt. WHISPER_POLISH_PROMPT can be:
    ///   "default" (the production single-polish prompt),
    ///   "strict"  (minimal-edit prompt that avoids over-rewriting),
    ///   or any other value, which is treated as a literal custom prompt.
    private static func polishPrompt(from env: [String: String]) -> String {
        switch env["WHISPER_POLISH_PROMPT"] {
        case nil, "", "default": return DualOpinionPolisher.singlePolishPrompt
        case "strict":           return DualOpinionPolisher.strictPolishPrompt
        case let custom?:        return custom
        }
    }

    // MARK: - Path helpers

    /// Derive the package root from this source file's location:
    /// .../Tests/YOLOWhispTests/Benchmark/ModelAccuracyBenchmarkTests.swift
    private static func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Benchmark
            .deletingLastPathComponent() // YOLOWhispTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
    }

    /// Resolve the `Benchmark/` directory. Honors WHISPER_BENCHMARK_DIR, else
    /// derives it from the package root.
    private static func benchmarkDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["WHISPER_BENCHMARK_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return packageRoot().appendingPathComponent("Benchmark", isDirectory: true)
    }
}
