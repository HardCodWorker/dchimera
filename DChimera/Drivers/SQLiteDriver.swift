import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite through the system libsqlite3.
final actor SQLiteDriver: DatabaseDriver {
    nonisolated let dialect: SQLDialect = .sqlite
    private var db: OpaquePointer?

    init(path: String, readOnly: Bool, create: Bool = false) throws {
        let expanded = (path as NSString).expandingTildeInPath
        guard !expanded.isEmpty else { throw DBError.message("Choose a SQLite file first.") }
        if !create && !FileManager.default.fileExists(atPath: expanded) {
            throw DBError.message("File not found: \(expanded)")
        }
        var handle: OpaquePointer?
        var flags = SQLITE_OPEN_FULLMUTEX
        flags |= readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | (create ? SQLITE_OPEN_CREATE : 0))
        let rc = sqlite3_open_v2(expanded, &handle, flags, nil)
        guard rc == SQLITE_OK, let handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code \(rc)"
            sqlite3_close(handle)
            throw DBError.message("Cannot open SQLite file: \(msg)")
        }
        sqlite3_busy_timeout(handle, 3000)
        sqlite3_exec(handle, "PRAGMA foreign_keys = ON", nil, nil, nil)
        db = handle
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    func close() async {
        if let db { sqlite3_close_v2(db) }
        db = nil
    }

    func serverVersion() async throws -> String {
        "SQLite " + String(cString: sqlite3_libversion())
    }

    private func error(_ prefix: String = "") -> DBError {
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "database is closed"
        return DBError.message(prefix + msg)
    }

    /// Runs every statement in `sql` and returns the result of the last one that produced rows
    /// (or of the last statement if none did).
    func execute(_ sql: String, rowLimit: Int?) async throws -> QueryResult {
        guard let db else { throw DBError.message("Database is closed") }
        let started = Date()
        var final = QueryResult()
        var sawRows = false
        var totalChanges = 0

        let utf8 = Array(sql.utf8CString)
        try utf8.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            var tail: UnsafePointer<CChar>? = base
            while let current = tail, current.pointee != 0 {
                var stmt: OpaquePointer?
                var next: UnsafePointer<CChar>?
                guard sqlite3_prepare_v2(db, current, -1, &stmt, &next) == SQLITE_OK else { throw error() }
                tail = next
                guard let stmt else { continue }
                defer { sqlite3_finalize(stmt) }

                let columnCount = Int(sqlite3_column_count(stmt))
                var result = QueryResult()
                if columnCount > 0 {
                    for i in 0..<columnCount {
                        result.columns.append(String(cString: sqlite3_column_name(stmt, Int32(i))))
                        result.columnTypes.append(sqlite3_column_decltype(stmt, Int32(i)).map { String(cString: $0) } ?? "")
                    }
                }
                while true {
                    let rc = sqlite3_step(stmt)
                    if rc == SQLITE_ROW {
                        if let rowLimit, result.rows.count >= rowLimit {
                            result.truncated = true
                            break
                        }
                        result.rows.append(Self.readRow(stmt, count: columnCount))
                    } else if rc == SQLITE_DONE {
                        break
                    } else {
                        throw error()
                    }
                }
                if columnCount > 0 {
                    final = result
                    sawRows = true
                } else {
                    totalChanges += Int(sqlite3_changes(db))
                    if !sawRows {
                        final = result
                        final.affectedRows = totalChanges
                        final.message = SQLText.firstKeyword(String(cString: sqlite3_sql(stmt))).uppercased()
                    }
                }
            }
        }
        final.duration = Date().timeIntervalSince(started)
        return final
    }

    private static func readRow(_ stmt: OpaquePointer, count: Int) -> [String?] {
        var row: [String?] = []
        row.reserveCapacity(count)
        for i in 0..<count {
            let idx = Int32(i)
            switch sqlite3_column_type(stmt, idx) {
            case SQLITE_NULL:
                row.append(nil)
            case SQLITE_BLOB:
                let n = Int(sqlite3_column_bytes(stmt, idx))
                if let p = sqlite3_column_blob(stmt, idx), n > 0 {
                    let data = Data(bytes: p, count: min(n, 64))
                    let hex = data.map { String(format: "%02x", $0) }.joined()
                    row.append("x'" + hex + (n > 64 ? "…" : "") + "'")
                } else {
                    row.append("x''")
                }
            default:
                if let text = sqlite3_column_text(stmt, idx) {
                    row.append(String(cString: text))
                } else {
                    row.append(nil)
                }
            }
        }
        return row
    }

    func listTables() async throws -> [TableRef] {
        let r = try await execute("SELECT name, type FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY name", rowLimit: nil)
        var tables: [TableRef] = []
        for row in r.rows {
            guard let name = row[0] else { continue }
            var t = TableRef(schema: "main", name: name, kind: row[1] == "view" ? .view : .table)
            if t.kind == .table, let n = try? await execute("SELECT count(*) FROM \(dialect.ident(name))", rowLimit: 1).rows.first?.first ?? nil {
                t.estimatedRows = Int(n)
            }
            tables.append(t)
        }
        return tables
    }

    func listColumns() async throws -> [ColumnBrief] {
        var all: [ColumnBrief] = []
        for t in try await listTables() {
            let info = try await execute("PRAGMA table_info(\(dialect.ident(t.name)))", rowLimit: nil)
            for row in info.rows {
                all.append(ColumnBrief(schema: "main", table: t.name, column: row[1] ?? "", type: row[2] ?? ""))
            }
        }
        return all
    }

    func details(of table: TableRef) async throws -> TableDetails {
        var details = TableDetails()
        let fks = try await execute("PRAGMA foreign_key_list(\(dialect.ident(table.name)))", rowLimit: nil)
        var fkByColumn: [String: String] = [:]
        var grouped: [String: ForeignKeyInfo] = [:]
        for row in fks.rows {
            let id = row[0] ?? "0", refTable = row[2] ?? "", from = row[3] ?? "", to = row[4] ?? ""
            fkByColumn[from] = "\(refTable).\(to)"
            var fk = grouped[id] ?? ForeignKeyInfo(name: "fk_\(table.name)_\(id)", columns: [], refTable: refTable, refColumns: [])
            fk.columns.append(from)
            fk.refColumns.append(to)
            grouped[id] = fk
        }
        details.foreignKeys = grouped.keys.sorted().compactMap { grouped[$0] }

        let info = try await execute("PRAGMA table_info(\(dialect.ident(table.name)))", rowLimit: nil)
        for row in info.rows {
            let name = row[1] ?? ""
            details.columns.append(ColumnInfo(
                name: name,
                type: (row[2] ?? "").isEmpty ? "ANY" : row[2]!,
                nullable: row[3] == "0",
                defaultValue: row[4],
                isPrimaryKey: (Int(row[5] ?? "0") ?? 0) > 0,
                references: fkByColumn[name]
            ))
        }

        let list = try await execute("PRAGMA index_list(\(dialect.ident(table.name)))", rowLimit: nil)
        for row in list.rows {
            guard let name = row[1] else { continue }
            let cols = try await execute("PRAGMA index_info(\(dialect.ident(name)))", rowLimit: nil).rows.compactMap { $0[2] }
            details.indexes.append(IndexInfo(name: name, columns: cols, unique: row[2] == "1", primary: row[3] == "pk", definition: nil))
        }
        let ddl = try await execute("SELECT sql FROM sqlite_master WHERE name = \(dialect.literal(table.name))", rowLimit: 1)
        details.ddl = ddl.rows.first?.first ?? nil
        for i in details.indexes.indices {
            let d = try await execute("SELECT sql FROM sqlite_master WHERE type = 'index' AND name = \(dialect.literal(details.indexes[i].name))", rowLimit: 1)
            details.indexes[i].definition = d.rows.first?.first ?? nil
        }
        return details
    }

    /// True when the table has a rowid (normal tables do, views and WITHOUT ROWID tables do not).
    func hasRowid(_ table: TableRef) async -> Bool {
        guard table.kind == .table else { return false }
        return (try? await execute("SELECT rowid FROM \(dialect.ident(table.name)) LIMIT 0", rowLimit: 0)) != nil
    }
}
