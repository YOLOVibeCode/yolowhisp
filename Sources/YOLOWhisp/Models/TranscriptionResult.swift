import Foundation

public struct TranscriptionResult {
    public let text: String
    public let duration: TimeInterval
    public let modelUsed: String
    public let timestamp: Date

    public init(text: String, duration: TimeInterval, modelUsed: String, timestamp: Date = Date()) {
        self.text = text
        self.duration = duration
        self.modelUsed = modelUsed
        self.timestamp = timestamp
    }
}
