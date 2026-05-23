import Foundation

public protocol ModelManaging {
    func availableModels() -> [WhisperModel]
    func loadModel(_ model: WhisperModel) throws
    var currentModel: WhisperModel? { get }
}
