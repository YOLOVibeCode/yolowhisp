import Foundation

public final class HistoryManager {
    private let store: HistoryStore

    public init(store: HistoryStore) {
        self.store = store
    }

    /// Convenience initializer using the default production database path.
    public convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("YOLOWhisp")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("history.db").path
        self.init(store: HistoryStore(databasePath: dbPath))
    }

    public func record(entry: HistoryEntry) throws {
        try store.save(entry: entry)
    }

    public func recentEntries(limit: Int = 50) throws -> [HistoryEntry] {
        try store.entries(limit: limit)
    }

    public func applyRetention(days: Int) throws {
        try store.applyRetention(days: days)
    }
}
