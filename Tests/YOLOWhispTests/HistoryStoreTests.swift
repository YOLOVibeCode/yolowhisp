import XCTest
@testable import YOLOWhisp

final class HistoryStoreTests: XCTestCase {
    func testSaveAndRetrieve() throws {
        let store = HistoryStore(databasePath: ":memory:")
        let entry = HistoryEntry(rawText: "hello world", processedText: "Hello world.", duration: 1.5, modelUsed: "small", targetApp: "Notes")
        try store.save(entry: entry)
        let results = try store.entries(limit: 10)
        XCTAssertEqual(results.count, 1)
        let r = results[0]
        XCTAssertEqual(r.id, entry.id)
        XCTAssertEqual(r.rawText, "hello world")
        XCTAssertEqual(r.processedText, "Hello world.")
        XCTAssertEqual(r.duration, 1.5, accuracy: 0.001)
        XCTAssertEqual(r.modelUsed, "small")
        XCTAssertEqual(r.targetApp, "Notes")
        XCTAssertEqual(r.timestamp.timeIntervalSince1970, entry.timestamp.timeIntervalSince1970, accuracy: 0.001)
    }

    func testSearchFindsMatch() throws {
        let store = HistoryStore(databasePath: ":memory:")
        try store.save(entry: HistoryEntry(rawText: "apple pie", duration: 1.0, modelUsed: "small"))
        try store.save(entry: HistoryEntry(rawText: "banana split", duration: 1.0, modelUsed: "small"))
        try store.save(entry: HistoryEntry(rawText: "cherry apple tart", processedText: nil, duration: 1.0, modelUsed: "small"))
        let results = try store.search(query: "apple")
        XCTAssertEqual(results.count, 2)
    }

    func testSearchFindsInProcessedText() throws {
        let store = HistoryStore(databasePath: ":memory:")
        try store.save(entry: HistoryEntry(rawText: "something", processedText: "unique keyword here", duration: 1.0, modelUsed: "small"))
        let results = try store.search(query: "unique keyword")
        XCTAssertEqual(results.count, 1)
    }

    func testSearchNoMatch() throws {
        let store = HistoryStore(databasePath: ":memory:")
        try store.save(entry: HistoryEntry(rawText: "hello", duration: 1.0, modelUsed: "small"))
        let results = try store.search(query: "xyz_not_found")
        XCTAssertTrue(results.isEmpty)
    }

    func testDeleteRemovesEntry() throws {
        let store = HistoryStore(databasePath: ":memory:")
        let entry = HistoryEntry(rawText: "to delete", duration: 1.0, modelUsed: "small")
        try store.save(entry: entry)
        try store.delete(id: entry.id)
        let results = try store.entries(limit: 10)
        XCTAssertEqual(results.count, 0)
    }

    func testEntriesLimitRespected() throws {
        let store = HistoryStore(databasePath: ":memory:")
        for i in 0..<20 {
            try store.save(entry: HistoryEntry(rawText: "entry \(i)", duration: 1.0, modelUsed: "small"))
        }
        let results = try store.entries(limit: 5)
        XCTAssertEqual(results.count, 5)
    }

    func testEntriesOrderedByTimestamp() throws {
        let store = HistoryStore(databasePath: ":memory:")
        let old = HistoryEntry(timestamp: Date(timeIntervalSince1970: 1000), rawText: "old", duration: 1.0, modelUsed: "small")
        let mid = HistoryEntry(timestamp: Date(timeIntervalSince1970: 2000), rawText: "mid", duration: 1.0, modelUsed: "small")
        let new = HistoryEntry(timestamp: Date(timeIntervalSince1970: 3000), rawText: "new", duration: 1.0, modelUsed: "small")
        try store.save(entry: old)
        try store.save(entry: new)
        try store.save(entry: mid)
        let results = try store.entries(limit: 10)
        XCTAssertEqual(results[0].rawText, "new")
        XCTAssertEqual(results[1].rawText, "mid")
        XCTAssertEqual(results[2].rawText, "old")
    }

    func testRetentionDeletesOld() throws {
        let store = HistoryStore(databasePath: ":memory:")
        let oldEntry = HistoryEntry(timestamp: Date(timeIntervalSinceNow: -8 * 86400), rawText: "old", duration: 1.0, modelUsed: "small")
        try store.save(entry: oldEntry)
        try store.applyRetention(days: 7)
        let results = try store.entries(limit: 10)
        XCTAssertEqual(results.count, 0)
    }

    func testRetentionKeepsRecent() throws {
        let store = HistoryStore(databasePath: ":memory:")
        let recent = HistoryEntry(rawText: "recent", duration: 1.0, modelUsed: "small")
        try store.save(entry: recent)
        try store.applyRetention(days: 7)
        let results = try store.entries(limit: 10)
        XCTAssertEqual(results.count, 1)
    }

    func testSQLitePersistence() throws {
        let tmpPath = NSTemporaryDirectory() + "yolowhisp_test_\(UUID().uuidString).db"
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let entry = HistoryEntry(rawText: "persistent", duration: 2.0, modelUsed: "large")
        do {
            let store = HistoryStore(databasePath: tmpPath)
            try store.save(entry: entry)
        }
        do {
            let store = HistoryStore(databasePath: tmpPath)
            let results = try store.entries(limit: 10)
            XCTAssertEqual(results.count, 1)
            XCTAssertEqual(results[0].rawText, "persistent")
            XCTAssertEqual(results[0].id, entry.id)
        }
    }
}
