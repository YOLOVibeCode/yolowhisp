import Foundation
import SQLite3

/// Tells SQLite to make its own private copy of bound text immediately.
/// Without this (the default `nil`/STATIC destructor), SQLite holds onto the
/// caller's pointer — which, for `(string as NSString).utf8String`, points into
/// a temporary that may be freed before the statement steps.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class HistoryStore: HistoryStoring {
    private var db: OpaquePointer?

    /// Use `:memory:` for tests, file path for production
    public init(databasePath: String = ":memory:") {
        guard sqlite3_open(databasePath, &db) == SQLITE_OK else {
            fatalError("Unable to open database at \(databasePath)")
        }
        let createSQL = """
            CREATE TABLE IF NOT EXISTS history (
                id TEXT PRIMARY KEY,
                timestamp REAL NOT NULL,
                raw_text TEXT NOT NULL,
                processed_text TEXT,
                duration REAL NOT NULL,
                model_used TEXT NOT NULL,
                target_app TEXT
            )
            """
        var errMsg: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, createSQL, nil, nil, &errMsg) == SQLITE_OK else {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            fatalError("Failed to create table: \(msg)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    public func save(entry: HistoryEntry) throws {
        let sql = "INSERT INTO history (id, timestamp, raw_text, processed_text, duration, model_used, target_app) VALUES (?, ?, ?, ?, ?, ?, ?)"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = entry.id.uuidString
        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, entry.timestamp.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, (entry.rawText as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if let pt = entry.processedText {
            sqlite3_bind_text(stmt, 4, (pt as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 4)
        }
        sqlite3_bind_double(stmt, 5, entry.duration)
        sqlite3_bind_text(stmt, 6, (entry.modelUsed as NSString).utf8String, -1, SQLITE_TRANSIENT)
        if let ta = entry.targetApp {
            sqlite3_bind_text(stmt, 7, (ta as NSString).utf8String, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 7)
        }

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(errorMessage)
        }
    }

    public func search(query: String) throws -> [HistoryEntry] {
        let sql = "SELECT id, timestamp, raw_text, processed_text, duration, model_used, target_app FROM history WHERE raw_text LIKE ? OR processed_text LIKE ? ORDER BY timestamp DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        let pattern = "%\(query)%"
        sqlite3_bind_text(stmt, 1, (pattern as NSString).utf8String, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, (pattern as NSString).utf8String, -1, SQLITE_TRANSIENT)

        return try readEntries(from: stmt)
    }

    public func delete(id: UUID) throws {
        let sql = "DELETE FROM history WHERE id = ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        let idStr = id.uuidString
        sqlite3_bind_text(stmt, 1, (idStr as NSString).utf8String, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(errorMessage)
        }
    }

    public func entries(limit: Int) throws -> [HistoryEntry] {
        let sql = "SELECT id, timestamp, raw_text, processed_text, duration, model_used, target_app FROM history ORDER BY timestamp DESC LIMIT ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(limit))

        return try readEntries(from: stmt)
    }

    public func applyRetention(days: Int) throws {
        let cutoff = Date().timeIntervalSince1970 - Double(days) * 86400
        let sql = "DELETE FROM history WHERE timestamp < ?"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(errorMessage)
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_double(stmt, 1, cutoff)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw SQLiteError.step(errorMessage)
        }
    }

    // MARK: - Private

    private var errorMessage: String {
        if let msg = sqlite3_errmsg(db) {
            return String(cString: msg)
        }
        return "unknown error"
    }

    private func readEntries(from stmt: OpaquePointer?) throws -> [HistoryEntry] {
        var results: [HistoryEntry] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idCStr = sqlite3_column_text(stmt, 0),
                  let id = UUID(uuidString: String(cString: idCStr)),
                  let rawCStr = sqlite3_column_text(stmt, 2),
                  let modelCStr = sqlite3_column_text(stmt, 5) else {
                continue
            }

            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let rawText = String(cString: rawCStr)
            let processedText: String? = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
            let duration = sqlite3_column_double(stmt, 4)
            let modelUsed = String(cString: modelCStr)
            let targetApp: String? = sqlite3_column_text(stmt, 6).map { String(cString: $0) }

            results.append(HistoryEntry(
                id: id,
                timestamp: timestamp,
                rawText: rawText,
                processedText: processedText,
                duration: duration,
                modelUsed: modelUsed,
                targetApp: targetApp
            ))
        }
        return results
    }

    private enum SQLiteError: Error {
        case prepare(String)
        case step(String)
    }
}
