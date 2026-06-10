import Foundation

/// Text-similarity metrics used by the model accuracy benchmark.
///
/// - WER (Word Error Rate): edit distance over normalized words / reference
///   word count. Lower is better; 0 means a perfect word-level match.
/// - CER (Character Error Rate): edit distance over raw characters / reference
///   character count. Captures fine-grained spelling/punctuation differences.
/// - Punctuation F1: precision/recall/F1 over the multiset of punctuation
///   marks, so we can score how well a model recovers punctuation specifically.
enum AccuracyMetrics {

    // MARK: Normalization

    /// Lowercased, punctuation-stripped, whitespace-collapsed word list.
    /// Used for WER so that "Hello, world!" and "hello world" compare as equal
    /// at the word level (punctuation is scored separately).
    static func normalizedWords(_ text: String) -> [String] {
        var out = ""
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.unicodeScalars.append(scalar)
            } else {
                out.append(" ")
            }
        }
        return out.lowercased().split(separator: " ").map(String.init)
    }

    /// Maps spelled-out numbers to their digit form so "three" and "3" compare
    /// as equal. Covers the common single-token cases; compound numbers
    /// ("twenty five") are left as separate tokens, which is fine for scoring.
    static let numberWords: [String: String] = [
        "zero": "0", "one": "1", "two": "2", "three": "3", "four": "4",
        "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9",
        "ten": "10", "eleven": "11", "twelve": "12", "thirteen": "13",
        "fourteen": "14", "fifteen": "15", "sixteen": "16", "seventeen": "17",
        "eighteen": "18", "nineteen": "19", "twenty": "20", "thirty": "30",
        "forty": "40", "fifty": "50", "sixty": "60", "seventy": "70",
        "eighty": "80", "ninety": "90", "hundred": "100", "thousand": "1000",
        "million": "1000000",
    ]

    /// Word list normalized for a *semantic* comparison: same as `normalizedWords`
    /// but spelled-out numbers are converted to digits. This avoids penalizing
    /// purely cosmetic differences like "3 oranges" vs "three oranges".
    static func semanticWords(_ text: String) -> [String] {
        normalizedWords(text).map { numberWords[$0] ?? $0 }
    }

    // MARK: Edit distance

    /// Classic Levenshtein (insert/delete/substitute = cost 1) over any
    /// Equatable sequence, using two rolling rows for O(n) memory.
    static func editDistance<Element: Equatable>(_ a: [Element], _ b: [Element]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)

        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = Swift.min(
                    previous[j] + 1,        // deletion
                    current[j - 1] + 1,     // insertion
                    previous[j - 1] + substitutionCost // substitution
                )
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    // MARK: WER / CER

    /// Word Error Rate. Can exceed 1.0 when the hypothesis inserts many extra
    /// words; callers may clamp for display.
    static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = normalizedWords(reference)
        let hyp = normalizedWords(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    /// Word Error Rate after number normalization. Treats "3" and "three" as
    /// equal, so it reflects meaning rather than cosmetic formatting.
    static func semanticWordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = semanticWords(reference)
        let hyp = semanticWords(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    /// Character Error Rate over lowercased raw text (punctuation included).
    static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = Array(reference.lowercased())
        let hyp = Array(hypothesis.lowercased())
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(ref.count)
    }

    // MARK: Punctuation

    static let punctuationMarks: Set<Character> = [
        ".", ",", "?", "!", ";", ":", "'", "\"", "-", "—", "…", "(", ")"
    ]

    static func punctuationCounts(_ text: String) -> [Character: Int] {
        var counts: [Character: Int] = [:]
        for ch in text where punctuationMarks.contains(ch) {
            counts[ch, default: 0] += 1
        }
        return counts
    }

    struct PunctuationScore {
        let precision: Double
        let recall: Double
        let f1: Double
    }

    /// F1 over the multiset of punctuation marks. A model that omits all
    /// punctuation scores recall 0; one that hallucinates extra marks scores
    /// lower precision.
    static func punctuationScore(reference: String, hypothesis: String) -> PunctuationScore {
        let refCounts = punctuationCounts(reference)
        let hypCounts = punctuationCounts(hypothesis)

        var overlap = 0
        for (mark, count) in refCounts {
            overlap += Swift.min(count, hypCounts[mark] ?? 0)
        }
        let refTotal = refCounts.values.reduce(0, +)
        let hypTotal = hypCounts.values.reduce(0, +)

        let precision: Double = hypTotal == 0 ? (refTotal == 0 ? 1 : 0) : Double(overlap) / Double(hypTotal)
        let recall: Double = refTotal == 0 ? 1 : Double(overlap) / Double(refTotal)
        let f1: Double = (precision + recall) == 0 ? 0 : 2 * precision * recall / (precision + recall)
        return PunctuationScore(precision: precision, recall: recall, f1: f1)
    }

    // MARK: Convenience

    /// Word-level accuracy in [0, 1], derived from WER and clamped.
    static func wordAccuracy(reference: String, hypothesis: String) -> Double {
        max(0, 1 - wordErrorRate(reference: reference, hypothesis: hypothesis))
    }
}
