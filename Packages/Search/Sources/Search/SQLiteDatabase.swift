import Foundation
import SQLite3

/// What went wrong talking to the index's database.
public struct SearchIndexError: Error, CustomStringConvertible, Sendable {
    public let code: Int32
    public let message: String

    public var description: String { "SQLite error \(code): \(message)" }
}

/// A value bound to a statement's parameter.
enum SQLiteValue {
    case int(Int64)
    case double(Double)
    case text(String)
    case null

    init(_ date: Date?) {
        self = date.map { .double($0.timeIntervalSince1970) } ?? .null
    }

    init(_ bool: Bool) {
        self = .int(bool ? 1 : 0)
    }
}

/// One result row, valid only inside the `query` callback that hands it out.
struct SQLiteRow {
    fileprivate let statement: OpaquePointer

    func int(_ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    func double(_ column: Int32) -> Double? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_double(statement, column)
    }

    func date(_ column: Int32) -> Date? {
        double(column).map(Date.init(timeIntervalSince1970:))
    }

    func text(_ column: Int32) -> String? {
        sqlite3_column_text(statement, column).map { String(cString: $0) }
    }
}

/// One connection to a SQLite database, with its statements cached. Not thread-safe: each one lives
/// inside a single actor.
final class SQLiteDatabase {
    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Couldn't open the database."
            sqlite3_close_v2(handle)
            throw SearchIndexError(code: result, message: message)
        }
        self.handle = handle
        // The writer commits small transactions; a reader that meets one waits instead of failing.
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit {
        for statement in statements.values {
            sqlite3_finalize(statement)
        }
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw failure(result) }
    }

    /// Runs `sql` with `bindings` (`?` parameters, in order) and hands each result row to `row`.
    func query(_ sql: String, _ bindings: [SQLiteValue] = [], row: (SQLiteRow) throws -> Void = { _ in }) throws {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        for (offset, value) in bindings.enumerated() {
            try bind(value, at: Int32(offset + 1), in: statement)
        }
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return }
            guard result == SQLITE_ROW else { throw failure(result) }
            try row(SQLiteRow(statement: statement))
        }
    }

    var lastInsertedRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let value = try body()
            try execute("COMMIT")
            return value
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    /// Forgets cached statements, for after the schema they were prepared against was dropped.
    func finalizeStatements() {
        for statement in statements.values {
            sqlite3_finalize(statement)
        }
        statements = [:]
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] { return statement }
        // Filters make many shapes of the same query; keep the cache from growing without end.
        if statements.count > 64 {
            finalizeStatements()
        }
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        guard result == SQLITE_OK, let statement else { throw failure(result) }
        statements[sql] = statement
        return statement
    }

    private func bind(_ value: SQLiteValue, at index: Int32, in statement: OpaquePointer) throws {
        // SQLITE_TRANSIENT: SQLite copies the text before the Swift string goes away.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let result =
            switch value {
            case .int(let int): sqlite3_bind_int64(statement, index, int)
            case .double(let double): sqlite3_bind_double(statement, index, double)
            case .text(let text): sqlite3_bind_text(statement, index, text, -1, transient)
            case .null: sqlite3_bind_null(statement, index)
            }
        guard result == SQLITE_OK else { throw failure(result) }
    }

    private func failure(_ code: Int32) -> SearchIndexError {
        SearchIndexError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }
}
