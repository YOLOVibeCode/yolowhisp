import Foundation

public struct HistoryEntry: Identifiable {
    public let id: UUID
    public let timestamp: Date
    public let rawText: String
    public let processedText: String?
    public let duration: TimeInterval
    public let modelUsed: String
    public let targetApp: String?

    public init(id: UUID = UUID(), timestamp: Date = Date(), rawText: String,
                processedText: String? = nil, duration: TimeInterval,
                modelUsed: String, targetApp: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.processedText = processedText
        self.duration = duration
        self.modelUsed = modelUsed
        self.targetApp = targetApp
    }
}
