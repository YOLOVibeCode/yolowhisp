import Foundation
import os

/// Lightweight app logging: mirrors to the unified log (Console.app) and to a
/// rolling file under Application Support so failures are inspectable after the
/// fact — including from the in-app Diagnostics window.
public enum AppLog {
    private static let logger = Logger(subsystem: "com.noctusoft.yolowhisp", category: "app")
    private static let queue = DispatchQueue(label: "com.noctusoft.yolowhisp.log")
    private static let maxBytes = 512 * 1024

    /// `~/Library/Application Support/YOLOWhisp/yolowhisp.log`
    public static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("YOLOWhisp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("yolowhisp.log")
    }()

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        queue.async { append("INFO", message) }
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        queue.async { append("ERROR", message) }
    }

    /// Last `count` lines of the log file (for the Diagnostics view).
    public static func recentLines(_ count: Int = 300) -> String {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .suffix(count)
            .joined(separator: "\n")
    }

    /// Install a handler that records uncaught Objective-C exceptions before
    /// the process dies. (Hard signals/Swift traps are still captured by the
    /// system .ips crash reports.)
    public static func installCrashHandlers() {
        NSSetUncaughtExceptionHandler { exception in
            let stack = exception.callStackSymbols.joined(separator: "\n")
            let msg = "UNCAUGHT EXCEPTION: \(exception.name.rawValue) — \(exception.reason ?? "")\n\(stack)"
            // Write synchronously: the process is about to terminate, so a
            // queued async write would never flush.
            AppLog.writeSync("FATAL", msg)
        }
    }

    // MARK: - File writing

    private static func append(_ level: String, _ message: String) {
        writeSync(level, message)
        rotateIfNeeded()
    }

    private static func writeSync(_ level: String, _ message: String) {
        let line = "\(timestamp()) [\(level)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: data)
        } else if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int,
              size > maxBytes,
              let data = try? Data(contentsOf: fileURL) else { return }
        // Keep the most recent half.
        let tail = data.suffix(maxBytes / 2)
        try? tail.write(to: fileURL)
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f.string(from: Date())
    }
}
