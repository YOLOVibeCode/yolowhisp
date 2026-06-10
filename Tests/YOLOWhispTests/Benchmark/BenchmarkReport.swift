import Foundation

/// Builds the human-readable markdown report from benchmark results. Pure
/// (string in, string out) so it can be unit-tested with synthetic results.
enum BenchmarkReport {

    /// Aggregated accuracy for one (model, prompt) configuration.
    struct Summary: Equatable {
        let model: String
        let promptMode: String
        let meanWER: Double
        let meanSemanticWER: Double
        let meanCER: Double
        let meanPunctuationF1: Double
        let realTimeFactor: Double

        // Final-stage AI polish aggregates (nil when polish wasn't run).
        let meanPolishedWER: Double?
        let meanPolishedSemanticWER: Double?
        let meanPolishedPunctuationF1: Double?

        var wordAccuracy: Double { max(0, 1 - meanWER) }
        var semanticWordAccuracy: Double { max(0, 1 - meanSemanticWER) }
        var polishedWordAccuracy: Double? { meanPolishedWER.map { max(0, 1 - $0) } }
        var polishedSemanticWordAccuracy: Double? { meanPolishedSemanticWER.map { max(0, 1 - $0) } }
    }

    /// Collapse per-sample results into one summary per (model, prompt),
    /// ranked by mean WER ascending (ties broken by higher punctuation F1).
    static func summarize(_ results: [BenchmarkRunResult]) -> [Summary] {
        struct Key: Hashable { let model: String; let prompt: String }
        var grouped: [Key: [BenchmarkRunResult]] = [:]
        for r in results {
            grouped[Key(model: r.model, prompt: r.promptMode), default: []].append(r)
        }

        var summaries: [Summary] = []
        for (key, runs) in grouped {
            let n = Double(runs.count)
            let meanWER = runs.map(\.rawScores.wer).reduce(0, +) / n
            let meanSemanticWER = runs.map(\.rawScores.semanticWER).reduce(0, +) / n
            let meanCER = runs.map(\.rawScores.cer).reduce(0, +) / n
            let meanPunct = runs.map(\.rawScores.punctuationF1).reduce(0, +) / n
            let totalAudio = runs.map(\.audioSeconds).reduce(0, +)
            let totalProc = runs.map(\.processingSeconds).reduce(0, +)
            let rtf = totalAudio > 0 ? totalProc / totalAudio : 0

            let polished = runs.compactMap(\.polishedScores)
            let meanPolishedWER = polished.isEmpty ? nil
                : polished.map(\.wer).reduce(0, +) / Double(polished.count)
            let meanPolishedSemanticWER = polished.isEmpty ? nil
                : polished.map(\.semanticWER).reduce(0, +) / Double(polished.count)
            let meanPolishedPunct = polished.isEmpty ? nil
                : polished.map(\.punctuationF1).reduce(0, +) / Double(polished.count)

            summaries.append(Summary(
                model: key.model, promptMode: key.prompt,
                meanWER: meanWER, meanSemanticWER: meanSemanticWER,
                meanCER: meanCER, meanPunctuationF1: meanPunct,
                realTimeFactor: rtf,
                meanPolishedWER: meanPolishedWER,
                meanPolishedSemanticWER: meanPolishedSemanticWER,
                meanPolishedPunctuationF1: meanPolishedPunct
            ))
        }

        // Rank by the fairer semantic WER (ties broken by punctuation F1).
        summaries.sort {
            $0.meanSemanticWER != $1.meanSemanticWER
                ? $0.meanSemanticWER < $1.meanSemanticWER
                : $0.meanPunctuationF1 > $1.meanPunctuationF1
        }
        return summaries
    }

    static func markdown(results: [BenchmarkRunResult], sampleCount: Int) -> String {
        let summaries = summarize(results)
        let didPolish = results.contains { $0.didPolish }

        var lines: [String] = []
        lines.append("# YOLOWhisp Model Accuracy Benchmark")
        lines.append("")
        lines.append("Samples: \(sampleCount)")
        lines.append("")
        lines.append("Ranked by mean Semantic WER (number-normalized; lower is better), tie-broken by punctuation F1.")
        lines.append("")
        lines.append("| Rank | Model | Prompt | Sem Acc | Word Acc | Sem WER | WER | CER | Punct F1 | Speed (xRT) |")
        lines.append("|------|-------|--------|---------|----------|---------|-----|-----|----------|-------------|")
        for (i, s) in summaries.enumerated() {
            lines.append(String(format: "| %d | %@ | %@ | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.1f%% | %.2f | %.2fx |",
                                i + 1, s.model, s.promptMode,
                                s.semanticWordAccuracy * 100, s.wordAccuracy * 100,
                                s.meanSemanticWER * 100, s.meanWER * 100, s.meanCER * 100,
                                s.meanPunctuationF1, s.realTimeFactor))
        }

        if let best = summaries.first {
            lines.append("")
            lines.append(String(format: "Best (raw): **%@** (%@) — %.1f%% semantic accuracy, punctuation F1 %.2f.",
                                best.model, best.promptMode, best.semanticWordAccuracy * 100, best.meanPunctuationF1))
        }

        // Final stage: AI polish comparison.
        if didPolish {
            lines.append("")
            lines.append("## AI Polish (final stage)")
            lines.append("")
            lines.append("Raw transcription vs. the same text after AI Polish. Δ uses Semantic WER (positive = polish helped).")
            lines.append("")
            lines.append("| Model | Prompt | Raw Sem WER | Polished Sem WER | Δ Sem WER | Raw Punct F1 | Polished Punct F1 |")
            lines.append("|-------|--------|-------------|------------------|-----------|--------------|-------------------|")
            for s in summaries {
                guard let pSem = s.meanPolishedSemanticWER, let pPunct = s.meanPolishedPunctuationF1 else { continue }
                let delta = (s.meanSemanticWER - pSem) * 100 // positive => polish improved semantic WER
                lines.append(String(format: "| %@ | %@ | %.1f%% | %.1f%% | %+.1f%% | %.2f | %.2f |",
                                    s.model, s.promptMode, s.meanSemanticWER * 100, pSem * 100, delta,
                                    s.meanPunctuationF1, pPunct))
            }

            let polishedSummaries = summaries.filter { $0.meanPolishedSemanticWER != nil }
            if let bestPolished = polishedSummaries.min(by: { ($0.meanPolishedSemanticWER ?? 1) < ($1.meanPolishedSemanticWER ?? 1) }),
               let acc = bestPolished.polishedSemanticWordAccuracy {
                lines.append("")
                lines.append(String(format: "Best (after polish): **%@** (%@) — %.1f%% semantic accuracy.",
                                    bestPolished.model, bestPolished.promptMode, acc * 100))
            }

            let errors = results.compactMap { $0.polishError }
            if !errors.isEmpty {
                lines.append("")
                lines.append("> Note: \(errors.count) polish call(s) failed (e.g. provider unavailable). First error: \(errors[0])")
            }
        }

        // Per-sample detail so individual mistakes are inspectable.
        lines.append("")
        lines.append("## Per-sample transcriptions")
        lines.append("")
        let byConfig = Dictionary(grouping: results) { "\($0.model) / \($0.promptMode)" }
        for key in byConfig.keys.sorted() {
            lines.append("### \(key)")
            lines.append("")
            for r in byConfig[key]!.sorted(by: { $0.sampleID < $1.sampleID }) {
                lines.append("- `\(r.sampleID)` (WER \(String(format: "%.0f%%", r.rawScores.wer * 100)))")
                lines.append("  - ref: \(r.reference)")
                lines.append("  - hyp: \(r.rawHypothesis)")
                if let polished = r.polishedHypothesis, let ps = r.polishedScores {
                    lines.append("  - polished: \(polished) (WER \(String(format: "%.0f%%", ps.wer * 100)))")
                } else if let err = r.polishError {
                    lines.append("  - polished: <failed: \(err)>")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
