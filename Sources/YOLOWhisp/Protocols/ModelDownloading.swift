import Foundation

public protocol ModelDownloading {
    func download(model: String, progress: @escaping (Double) -> Void) async throws -> WhisperModel
    func availableRemoteModels() -> [String]
    func cancelDownload()
}
