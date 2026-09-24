import Foundation
import SQLite3

struct Note {
    let id: Int64
    let title: String
    let body: String
}

final class NotesStore {
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &database) == SQLITE_OK else {
            let error = failure()
            sqlite3_close(database)
            database = nil
            throw error
        }
        do {
            sqlite3_busy_timeout(database, 3000)
            try execute("PRAGMA journal_mode=DELETE")
            try execute("CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL, body TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)")
            try execute("PRAGMA user_version=1")
        } catch {
            sqlite3_close(database)
            database = nil
            throw error
        }
    }

    deinit { sqlite3_close(database) }

    func all() throws -> [Note] {
        let statement = try prepare("SELECT id, title, body FROM notes ORDER BY updated_at DESC, id DESC")
        defer { sqlite3_finalize(statement) }
        var notes: [Note] = []
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW {
            notes.append(Note(id: sqlite3_column_int64(statement, 0), title: text(statement, 1), body: text(statement, 2)))
            status = sqlite3_step(statement)
        }
        guard status == SQLITE_DONE else { throw failure() }
        return notes
    }

    func save(id: Int64?, title: String, body: String) throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw NSError(domain: "Notes", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enter a title before saving."]) }
        let sql = id == nil
            ? "INSERT INTO notes(title, body, created_at, updated_at) VALUES (?, ?, strftime('%Y-%m-%dT%H:%M:%fZ','now'), strftime('%Y-%m-%dT%H:%M:%fZ','now'))"
            : "UPDATE notes SET title=?, body=?, updated_at=strftime('%Y-%m-%dT%H:%M:%fZ','now') WHERE id=?"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_bind_text(statement, 1, title, -1, transient) == SQLITE_OK,
              sqlite3_bind_text(statement, 2, body, -1, transient) == SQLITE_OK else { throw failure() }
        if let id = id { sqlite3_bind_int64(statement, 3, id) }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func delete(id: Int64) throws {
        let statement = try prepare("DELETE FROM notes WHERE id=?")
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw failure() }
    }

    func addSamples() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            for index in 1...50 {
                try save(id: nil, title: "Sample note \(index)", body: "A local SQLite note for scrolling and persistence checks.\nSample \(index) — café ☕")
            }
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement = statement else { throw failure() }
        return statement
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw failure() }
    }

    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func failure() -> Error {
        NSError(domain: "SQLite", code: Int(sqlite3_errcode(database)), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(database))])
    }
}
