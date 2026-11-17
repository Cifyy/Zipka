//
//  SQLiteDatabase.swift
//  Zipka
//

import Foundation
import SQLite3

nonisolated struct SQLiteError: Error, CustomStringConvertible {
    let code: Int32
    let message: String

    var description: String { "SQLite error \(code): \(message)" }
}

/// Thin wrapper over the system SQLite library. Not thread-safe: use one instance from one place at a time.
nonisolated final class SQLiteDatabase {
    fileprivate let handle: OpaquePointer

    init(url: URL, readOnly: Bool) throws {
        var handle: OpaquePointer?
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let result = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open database"
            sqlite3_close_v2(handle)
            throw SQLiteError(code: result, message: message)
        }
        self.handle = handle
    }

    deinit {
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(handle, sql, nil, nil, &error)
        guard result == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(error)
            throw SQLiteError(code: result, message: message)
        }
    }

    func prepare(_ sql: String) throws -> SQLiteStatement {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else { throw lastError(result) }
        return SQLiteStatement(statement: statement, database: self)
    }

    fileprivate func lastError(_ code: Int32) -> SQLiteError {
        SQLiteError(code: code, message: String(cString: sqlite3_errmsg(handle)))
    }
}

/// A prepared statement. Bind parameters (1-based), then `step()` through rows or `run()` it.
nonisolated final class SQLiteStatement {
    private let statement: OpaquePointer
    private let database: SQLiteDatabase

    /// Tells SQLite to copy bound strings and blobs, since Swift owns the original memory.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    fileprivate init(statement: OpaquePointer, database: SQLiteDatabase) {
        self.statement = statement
        self.database = database
    }

    deinit {
        sqlite3_finalize(statement)
    }

    func bind(_ value: Int, at index: Int32) {
        sqlite3_bind_int64(statement, index, sqlite3_int64(value))
    }

    func bind(_ value: Double, at index: Int32) {
        sqlite3_bind_double(statement, index, value)
    }

    func bind(_ value: String?, at index: Int32) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, Self.transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    func bind(_ value: Int?, at index: Int32) {
        if let value { bind(value, at: index) } else { sqlite3_bind_null(statement, index) }
    }

    func bind(_ value: Data, at index: Int32) {
        value.withUnsafeBytes { bytes in
            _ = sqlite3_bind_blob(statement, index, bytes.baseAddress, Int32(bytes.count), Self.transient)
        }
    }

    /// Advances to the next row. Returns `false` when there are no more rows.
    func step() throws -> Bool {
        let result = sqlite3_step(statement)
        switch result {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw database.lastError(result)
        }
    }

    /// Executes the statement to completion and resets it for reuse.
    func run() throws {
        defer { reset() }
        while try step() {}
    }

    func reset() {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
    }

    func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(statement, column))
    }

    func optionalInt(_ column: Int32) -> Int? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : int(column)
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(statement, column)
    }

    func string(_ column: Int32) -> String {
        guard let text = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: text)
    }

    func optionalString(_ column: Int32) -> String? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : string(column)
    }

    func data(_ column: Int32) -> Data {
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0, let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: count)
    }
}
