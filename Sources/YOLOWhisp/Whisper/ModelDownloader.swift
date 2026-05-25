import Foundation

public enum ModelDownloadError: Error {
    case invalidModel(String)
    case networkError(String)
    case checksumMismatch
    case cancelled
}

public final class ModelDownloader: ModelDownloading {
    private let session: URLSession
    private var downloadTask: URLSessionDataTask?
    private let destinationDirectory: String

    private static let models = ["tiny", "base", "small", "medium", "large"]

    public static func downloadURL(for model: String) -> URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(model).bin")!
    }

    public init(session: URLSession = .shared, destinationDirectory: String? = nil) {
        self.session = session
        self.destinationDirectory = destinationDirectory ?? NSString("~/.local/share/whisper").expandingTildeInPath
    }

    public func availableRemoteModels() -> [String] { Self.models }

    public func download(model: String, progress: @escaping (Double) -> Void) async throws -> WhisperModel {
        guard Self.models.contains(model) else { throw ModelDownloadError.invalidModel(model) }

        let url = Self.downloadURL(for: model)
        let destPath = "\(destinationDirectory)/ggml-\(model).bin"
        let partialPath = destPath + ".partial"

        try FileManager.default.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)

        // Stream to disk rather than buffering the whole model (up to ~1.5GB)
        // in memory, writing to a .partial file we only move into place once
        // the download completes intact.
        let (bytes, response) = try await session.bytes(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelDownloadError.networkError("HTTP error")
        }
        let expectedBytes = httpResponse.expectedContentLength  // -1 if unknown

        try? FileManager.default.removeItem(atPath: partialPath)
        FileManager.default.createFile(atPath: partialPath, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: partialPath) else {
            throw ModelDownloadError.networkError("cannot open \(partialPath) for writing")
        }

        var received: Int64 = 0
        var buffer = Data()
        buffer.reserveCapacity(262_144)
        var lastReported = -1.0

        do {
            for try await byte in bytes {
                buffer.append(byte)
                received += 1
                if buffer.count >= 262_144 {
                    try handle.write(contentsOf: buffer)
                    buffer.removeAll(keepingCapacity: true)
                }
                if expectedBytes > 0 {
                    let fraction = min(0.99, Double(received) / Double(expectedBytes))
                    if fraction - lastReported >= 0.01 {
                        lastReported = fraction
                        progress(fraction)
                    }
                }
            }
            if !buffer.isEmpty { try handle.write(contentsOf: buffer) }
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(atPath: partialPath)
            throw ModelDownloadError.networkError(String(describing: error))
        }

        // Guard against a truncated download when the server told us the size.
        if expectedBytes > 0 && received != expectedBytes {
            try? FileManager.default.removeItem(atPath: partialPath)
            throw ModelDownloadError.networkError("incomplete download (\(received)/\(expectedBytes) bytes)")
        }

        // Atomically install the completed file.
        try? FileManager.default.removeItem(atPath: destPath)
        try FileManager.default.moveItem(atPath: partialPath, toPath: destPath)

        progress(1.0)
        return WhisperModel(name: "ggml-\(model)", path: destPath, size: UInt64(received))
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }
}
