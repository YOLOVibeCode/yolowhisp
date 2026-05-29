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
    /// Deliberately avoids `Bundle.module` — its generated accessor calls
    /// fatalError() when the SPM resource bundle isn't a "proper" bundle (in a
    /// packaged .app it's a flat dir), which would CRASH the app. Locate the
    /// file defensively and return nil if it isn't found.
    static func selfTestPCM() -> Data? {
        for url in candidateURLs() where FileManager.default.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url) { return pcm(fromWAV: data) }
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let u = Bundle.main.url(forResource: "selftest", withExtension: "wav") { urls.append(u) }
        guard let res = Bundle.main.resourceURL else { return urls }
        urls.append(res.appendingPathComponent("selftest.wav"))
        // SwiftPM resource bundles live as Resources/<Pkg>_<Target>.bundle and
        // may be flat or have Contents/Resources depending on packaging.
        if let items = try? FileManager.default.contentsOfDirectory(at: res, includingPropertiesForKeys: nil) {
            for item in items where item.pathExtension == "bundle" {
                urls.append(item.appendingPathComponent("selftest.wav"))
                urls.append(item.appendingPathComponent("Contents/Resources/selftest.wav"))
            }
        }
        return urls
    }

    /// Strip a WAV container to its raw PCM payload via the `data` subchunk.
    static func pcm(fromWAV data: Data) -> Data? {
        guard let r = data.range(of: Data("data".utf8)) else { return nil }
        let start = r.upperBound + 4 // skip the 4-byte chunk-size field
        guard start <= data.count else { return nil }
        return data.subdata(in: start..<data.count)
    }
}
