import XCTest
@testable import YOLOWhisp

final class AccuracyMetricsTests: XCTestCase {

    func testEditDistanceBasics() {
        XCTAssertEqual(AccuracyMetrics.editDistance(Array("kitten"), Array("sitting")), 3)
        XCTAssertEqual(AccuracyMetrics.editDistance(Array(""), Array("abc")), 3)
        XCTAssertEqual(AccuracyMetrics.editDistance(Array("abc"), Array("abc")), 0)
    }

    func testPerfectMatchHasZeroError() {
        let text = "Hello, how are you? I'm great!"
        XCTAssertEqual(AccuracyMetrics.wordErrorRate(reference: text, hypothesis: text), 0, accuracy: 1e-9)
        XCTAssertEqual(AccuracyMetrics.characterErrorRate(reference: text, hypothesis: text), 0, accuracy: 1e-9)
        XCTAssertEqual(AccuracyMetrics.punctuationScore(reference: text, hypothesis: text).f1, 1, accuracy: 1e-9)
    }

    func testWERIgnoresCaseAndPunctuation() {
        // Same words, different case + punctuation -> word error rate is 0.
        let ref = "Hello, world!"
        let hyp = "hello world"
        XCTAssertEqual(AccuracyMetrics.wordErrorRate(reference: ref, hypothesis: hyp), 0, accuracy: 1e-9)
    }

    func testWERCountsWordSubstitution() {
        // 1 substitution out of 3 reference words.
        let wer = AccuracyMetrics.wordErrorRate(reference: "the quick fox", hypothesis: "the quick dog")
        XCTAssertEqual(wer, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testPunctuationRecallDropsWhenMissing() {
        // Hypothesis drops all punctuation: recall should be 0, F1 0.
        let score = AccuracyMetrics.punctuationScore(
            reference: "Hello, world. Right?",
            hypothesis: "Hello world Right"
        )
        XCTAssertEqual(score.recall, 0, accuracy: 1e-9)
        XCTAssertEqual(score.f1, 0, accuracy: 1e-9)
    }

    func testPunctuationPrecisionDropsWhenHallucinated() {
        // Reference has none; hypothesis invents punctuation -> precision 0.
        let score = AccuracyMetrics.punctuationScore(
            reference: "hello world",
            hypothesis: "hello, world."
        )
        XCTAssertEqual(score.precision, 0, accuracy: 1e-9)
    }

    func testSemanticWERTreatsNumberWordsAsDigits() {
        // "3 oranges" vs "three oranges" is a real WER error but semantically 0.
        let ref = "She bought 3 oranges"
        let hyp = "She bought three oranges"
        XCTAssertGreaterThan(AccuracyMetrics.wordErrorRate(reference: ref, hypothesis: hyp), 0)
        XCTAssertEqual(AccuracyMetrics.semanticWordErrorRate(reference: ref, hypothesis: hyp), 0, accuracy: 1e-9)
    }

    func testSemanticWERStillCcountsRealErrors() {
        // Wrong word is still an error under semantic normalization.
        let wer = AccuracyMetrics.semanticWordErrorRate(reference: "buy three apples", hypothesis: "buy three oranges")
        XCTAssertEqual(wer, 1.0 / 3.0, accuracy: 1e-9)
    }

    func testWordAccuracyClampsToZero() {
        // Many inserted words make WER > 1; accuracy clamps at 0.
        let acc = AccuracyMetrics.wordAccuracy(reference: "hi", hypothesis: "hi there how are you")
        XCTAssertGreaterThanOrEqual(acc, 0)
    }
}
