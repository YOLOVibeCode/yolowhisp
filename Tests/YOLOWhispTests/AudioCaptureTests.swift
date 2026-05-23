import XCTest
@testable import YOLOWhisp

final class AudioCaptureTests: XCTestCase {
    func testConformsToProtocol() {
        let engine: any AudioCapturing = AudioCaptureEngine()
        XCTAssertNotNil(engine)
    }

    func testInitialStateIsNotCapturing() {
        let engine = AudioCaptureEngine()
        XCTAssertFalse(engine.isCapturing)
    }

    func testStopWithoutStartReturnsEmptyData() {
        let engine = AudioCaptureEngine()
        let data = engine.stopCapture()
        XCTAssertTrue(data.isEmpty)
        XCTAssertFalse(engine.isCapturing)
    }

    func testStartSetsIsCapturing() {
        let engine = AudioCaptureEngine()
        engine.startCapture()
        XCTAssertTrue(engine.isCapturing)
        // Clean up
        _ = engine.stopCapture()
    }

    func testStopResetsIsCapturing() {
        let engine = AudioCaptureEngine()
        engine.startCapture()
        XCTAssertTrue(engine.isCapturing)
        _ = engine.stopCapture()
        XCTAssertFalse(engine.isCapturing)
    }

    func testDoubleStartIsIdempotent() {
        let engine = AudioCaptureEngine()
        engine.startCapture()
        engine.startCapture() // Should not crash or double-tap
        XCTAssertTrue(engine.isCapturing)
        _ = engine.stopCapture()
    }

    func testDoubleStopIsIdempotent() {
        let engine = AudioCaptureEngine()
        engine.startCapture()
        _ = engine.stopCapture()
        let data = engine.stopCapture() // Second stop should be safe
        XCTAssertTrue(data.isEmpty)
    }

    func testWAVHeaderGeneration() {
        // Test the WAV header utility directly
        let pcmData = Data(repeating: 0, count: 32000) // 1 second of 16kHz 16-bit mono
        let wav = AudioCaptureEngine.createWAVData(from: pcmData, sampleRate: 16000, channels: 1, bitsPerSample: 16)

        // WAV header is 44 bytes
        XCTAssertEqual(wav.count, 44 + pcmData.count)

        // Check RIFF header
        let riff = String(data: wav[0..<4], encoding: .ascii)
        XCTAssertEqual(riff, "RIFF")

        // Check WAVE format
        let wave = String(data: wav[8..<12], encoding: .ascii)
        XCTAssertEqual(wave, "WAVE")

        // Check fmt chunk
        let fmt = String(data: wav[12..<16], encoding: .ascii)
        XCTAssertEqual(fmt, "fmt ")

        // Check data chunk
        let dataChunk = String(data: wav[36..<40], encoding: .ascii)
        XCTAssertEqual(dataChunk, "data")
    }

    func testSampleRateIs16kHz() {
        // Verify the engine's target format
        XCTAssertEqual(AudioCaptureEngine.targetSampleRate, 16000.0)
    }

    func testChannelCountIsMono() {
        XCTAssertEqual(AudioCaptureEngine.targetChannels, 1)
    }
}
