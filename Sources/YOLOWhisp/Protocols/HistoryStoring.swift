import Foundation

public protocol HistoryStoring {
    func save(entry: HistoryEntry) throws
    func search(query: String) throws -> [HistoryEntry]
    func delete(id: UUID) throws
    func entries(limit: Int) throws -> [HistoryEntry]
}
