import Foundation

public struct WhisperModel: Equatable {
    public let name: String
    public let path: String
    public let size: UInt64

    public init(name: String, path: String, size: UInt64) {
        self.name = name
        self.path = path
        self.size = size
    }
}
