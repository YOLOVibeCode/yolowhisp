import Foundation

/// Audio source that replays fixed PCM (e.g. the bundled self-test clip)
/// instead of the mic, so Diagnostics can drive the real pipeline headlessly.
final class FileAudioCapture: AudioCapturing {
    var isCapturing = false
    private let pcm: Data
    init(pcm: Data) { self.pcm = pcm }
    func startCapture() { isCapturing = true }
    func stopCapture() -> Data {
        isCapturing = false
        return pcm
    }
}

/// Output sink that records text instead of typing it — no real keystrokes,
/// clipboard, or accessibility writes touch the session during a self-test.
final class CapturingTextOutput: TextOutputting {
    let mode: OutputMode
    private(set) var captured: [String] = []
    init(mode: OutputMode = .simulatedKeystrokes) { self.mode = mode }
    func output(text: String) async throws { captured.append(text) }
}

/// No-op pill for headless self-tests (no floating UI).
final class NullPillDisplay: PillDisplaying {
    var position: CGPoint = .zero
    func show() {}
    func hide() {}
    func setState(_ state: PillState) {}
}

/// Bundled audio used by the end-to-end health check.
enum DiagnosticsSamples {
    /// Raw 16kHz mono PCM from the bundled selftest.wav, or nil if unavailable.
    static func selfTestPCM() -> Data? {
        guard let url = Bundle.module.url(forResource: "selftest", withExtension: "wav"),
              let data = try? Data(contentsOf: url) else { return nil }
        return pcm(fromWAV: data)
    }

    /// Strip a WAV container to its raw PCM payload via the `data` subchunk.
    static func pcm(fromWAV data: Data) -> Data? {
        guard let r = data.range(of: Data("data".utf8)) else { return nil }
        let start = r.upperBound + 4 // skip the 4-byte chunk-size field
        guard start <= data.count else { return nil }
        return data.subdata(in: start..<data.count)
    }
}
