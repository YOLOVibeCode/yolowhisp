import Foundation

public final class DoubleTapDetector {
    public let threshold: TimeInterval
    private var lastTapTime: Date?

    public init(threshold: TimeInterval = 0.3) {
        self.threshold = threshold
    }

    public func tap() -> Bool {
        let now = Date()
        defer { lastTapTime = now }
        guard let last = lastTapTime else { return false }
        return now.timeIntervalSince(last) < threshold
    }

    public func reset() {
        lastTapTime = nil
    }
}
