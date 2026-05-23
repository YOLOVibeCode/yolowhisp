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

        try FileManager.default.createDirectory(atPath: destinationDirectory, withIntermediateDirectories: true)

        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ModelDownloadError.networkError("HTTP error")
        }

        progress(1.0)

        try data.write(to: URL(fileURLWithPath: destPath))

        let size = UInt64(data.count)
        return WhisperModel(name: "ggml-\(model)", path: destPath, size: size)
    }

    public func cancelDownload() {
        downloadTask?.cancel()
    }
}
