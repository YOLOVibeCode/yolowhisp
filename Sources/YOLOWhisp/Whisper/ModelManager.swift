import Foundation

public final class ModelManager: ModelManaging {
    public private(set) var currentModel: WhisperModel?
    private let searchPaths: [String]

    public init(searchPaths: [String] = []) {
        if searchPaths.isEmpty {
            var paths = [
                NSHomeDirectory() + "/.local/share/whisper",
                "/usr/local/share/whisper",
                "/opt/homebrew/share/whisper",
            ]
            // The "complete" build bundles a model here.
            if let bundled = Bundle.main.resourceURL?.appendingPathComponent("whisper/models").path {
                paths.append(bundled)
            }
            self.searchPaths = paths
        } else {
            self.searchPaths = searchPaths
        }
    }

    public func availableModels() -> [WhisperModel] {
        let fm = FileManager.default
        var models: [WhisperModel] = []

        for searchPath in searchPaths {
            guard let contents = try? fm.contentsOfDirectory(atPath: searchPath) else { continue }
            for file in contents where file.hasPrefix("ggml-") && file.hasSuffix(".bin") {
                let fullPath = (searchPath as NSString).appendingPathComponent(file)
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath),
                      let size = attrs[.size] as? UInt64 else { continue }
                let name = String(file.dropFirst(5).dropLast(4)) // strip "ggml-" and ".bin"
                models.append(WhisperModel(name: name, path: fullPath, size: size))
            }
        }

        return models
    }

    public func loadModel(_ model: WhisperModel) throws {
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw ModelManagerError.modelNotFound(model.path)
        }
        currentModel = model
    }
}

public enum ModelManagerError: Error, Equatable {
    case modelNotFound(String)
}
