import XCTest
@testable import YOLOWhisp

final class AudioLevelTests: XCTestCase {
    func testComputeRMSSilence() {
        let samples: [Int16] = [0, 0, 0, 0]
        let rms = samples.withUnsafeBufferPointer { buf in
            AudioCaptureEngine.computeRMS(from: buf.baseAddress!, count: buf.count)
        }
        XCTAssertEqual(rms, 0.0, accuracy: 0.0001)
    }

    func testComputeRMSMaxVolume() {
        let samples: [Int16] = [Int16.max, Int16.max, Int16.max, Int16.max]
        let rms = samples.withUnsafeBufferPointer { buf in
            AudioCaptureEngine.computeRMS(from: buf.baseAddress!, count: buf.count)
        }
        XCTAssertEqual(rms, Float(Int16.max) / 32768.0, accuracy: 0.001)
    }

    func testComputeRMSKnownValues() {
        let samples: [Int16] = [1000, -1000, 1000, -1000]
        let rms = samples.withUnsafeBufferPointer { buf in
            AudioCaptureEngine.computeRMS(from: buf.baseAddress!, count: buf.count)
        }
        XCTAssertEqual(rms, 1000.0 / 32768.0, accuracy: 0.0001)
    }

    func testAudioLevelCallbackExists() {
        let engine = AudioCaptureEngine()
        XCTAssertNil(engine.audioLevelCallback)
        engine.audioLevelCallback = { _ in }
        XCTAssertNotNil(engine.audioLevelCallback)
    }
}
