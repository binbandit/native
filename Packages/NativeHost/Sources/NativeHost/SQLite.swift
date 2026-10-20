import Foundation

#if canImport(SQLite3)
import SQLite3
#else
import CSQLite
#endif

/// A thin wrapper over the system SQLite: one connection, prepared statements, typed binding. Owned
/// by one isolation domain (the host actor), so it does no locking of its own.
final class SQLiteDatabase {
    struct Failure: Error, LocalizedError {
        var code: Int32
        var message: String

        var errorDescription: String? { "SQLite error \(code): \(message)" }
    }

    enum Value: Hashable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
    }

    private let handle: OpaquePointer

    init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path(percentEncoded: false), &handle, flags, nil)
        guard code == SQLITE_OK, let handle else {
            let message =
                handle.map { String(cString: sqlite3_errmsg($0)) } ?? "can't open \(url.path(percentEncoded: false))"
            sqlite3_close(handle)
            throw Failure(code: code, message: message)
        }
        self.handle = handle
        sqlite3_busy_timeout(handle, 5_000)
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    /// Runs statements that take no parameters, such as schema changes and pragmas.
    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &error)
        guard code == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError
            sqlite3_free(error)
            throw Failure(code: code, message: message)
        }
    }

    func run(_ sql: String, _ values: Value...) throws {
        _ = try query(sql, values)
    }

    func query(_ sql: String, _ values: Value...) throws -> [[Value]] {
        try query(sql, values)
    }

    func query(_ sql: String, _ values: [Value]) throws -> [[Value]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw Failure(code: sqlite3_errcode(handle), message: "\(lastError) in: \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code =
                switch value {
                case .null: sqlite3_bind_null(statement, index)
                case .integer(let integer): sqlite3_bind_int64(statement, index, integer)
                case .real(let real): sqlite3_bind_double(statement, index, real)
                case .text(let text): sqlite3_bind_text(statement, index, text, -1, Self.transient)
                }
            guard code == SQLITE_OK else { throw Failure(code: code, message: lastError) }
        }
        var rows: [[Value]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw Failure(code: code, message: "\(lastError) in: \(sql)") }
            rows.append(
                (0..<sqlite3_column_count(statement)).map { column in
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: .integer(sqlite3_column_int64(statement, column))
                    case SQLITE_FLOAT: .real(sqlite3_column_double(statement, column))
                    case SQLITE_TEXT: .text(String(cString: sqlite3_column_text(statement, column)))
                    default: .null
                    }
                })
        }
        return rows
    }

    /// Runs `body` in one transaction: everything in it is durable together, or not at all.
    func transaction<Result>(_ body: () throws -> Result) throws -> Result {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(handle))
    }

    /// Tells SQLite to copy bound strings, since Swift's bridged buffers don't outlive the call.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

extension SQLiteDatabase.Value {
    var text: String? {
        if case .text(let text) = self { text } else { nil }
    }

    var integer: Int64? {
        if case .integer(let integer) = self { integer } else { nil }
    }

    var real: Double? {
        switch self {
        case .real(let real): real
        case .integer(let integer): Double(integer)
        default: nil
        }
    }

    var bool: Bool {
        integer.map { $0 != 0 } ?? false
    }

    var date: Date? {
        real.map(Date.init(timeIntervalSince1970:))
    }

    static func text(_ value: String?) -> Self {
        value.map(Self.text) ?? .null
    }

    static func date(_ value: Date?) -> Self {
        value.map { .real($0.timeIntervalSince1970) } ?? .null
    }

    static func bool(_ value: Bool) -> Self {
        .integer(value ? 1 : 0)
    }
}
