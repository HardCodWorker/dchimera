import Foundation
import Logging
import MySQLNIO
import NIOCore
import NIOPosix
import NIOSSL

/// MySQL / MariaDB through MySQLNIO. Row queries use the text protocol (values arrive as text);
/// other statements use the prepared protocol so the affected-row count is known.
final actor MySQLDriver: DatabaseDriver {
    nonisolated let dialect: SQLDialect = .mysql
    private let connection: MySQLConnection
    private let database: String

    private init(connection: MySQLConnection, database: String) {
        self.connection = connection
        self.database = database
    }

    static func connect(_ config: ConnectionConfig, password: String?) async throws -> MySQLDriver {
        let host = config.host.trimmingCharacters(in: .whitespaces)
        var logger = Logger(label: "dchimera.mysql")
        logger.logLevel = .error
        let address = try SocketAddress.makeAddressResolvingHost(host, port: config.port)
        let isIP = host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }

        func open(tls: TLSConfiguration?) async throws -> MySQLConnection {
            try await MySQLConnection.connect(
                to: address,
                username: config.user,
                database: config.database,
                password: (password?.isEmpty ?? true) ? nil : password,
                tlsConfiguration: tls,
                serverHostname: isIP ? nil : host,
                logger: logger,
                on: MultiThreadedEventLoopGroup.singleton.any()
            ).get()
        }

        var tls = TLSConfiguration.makeClientConfiguration()
        if config.sslMode != .verifyFull { tls.certificateVerification = .none }

        let connection: MySQLConnection
        do {
            switch config.sslMode {
            case .disable:
                connection = try await open(tls: nil)
            case .prefer:
                do { connection = try await open(tls: tls) } catch { connection = try await open(tls: nil) }
            case .require, .verifyFull:
                connection = try await open(tls: tls)
            }
        } catch {
            throw DBError.message(describe(error))
        }
        let driver = MySQLDriver(connection: connection, database: config.database)
        if config.readOnly {
            _ = try await driver.execute("SET SESSION TRANSACTION READ ONLY", rowLimit: nil)
        }
        return driver
    }

    func close() async {
        try? await connection.close().get()
    }

    func serverVersion() async throws -> String {
        "MySQL " + (try await strings("SELECT VERSION()").first ?? "?")
    }

    func execute(_ sql: String, rowLimit: Int?) async throws -> QueryResult {
        let started = Date()
        var result = QueryResult()
        do {
            if SQLText.returnsRows(sql) {
                result = try await textQuery(sql, rowLimit: rowLimit)
            } else {
                var affected: UInt64 = 0
                do {
                    let rows = try await connection.query(sql, [], onMetadata: { affected = $0.affectedRows }).get()
                    if let first = rows.first {
                        result.columns = first.columnDefinitions.map(\.name)
                        result.columnTypes = first.columnDefinitions.map { "\($0.columnType)" }
                        result.rows = rows.prefix(rowLimit ?? Int.max).map { row in
                            row.columnDefinitions.indices.map { i in
                                guard i < row.values.count, let buffer = row.values[i] else { return nil }
                                return MySQLData(type: row.columnDefinitions[i].columnType, format: row.format, buffer: buffer).description
                            }
                        }
                    }
                    result.affectedRows = Int(affected)
                } catch {
                    // Some statements cannot be prepared; run them through the text protocol instead.
                    result = try await textQuery(sql, rowLimit: rowLimit)
                }
                if result.columns.isEmpty {
                    result.message = SQLText.firstKeyword(sql).uppercased()
                }
            }
        } catch {
            throw DBError.message(Self.describe(error))
        }
        result.duration = Date().timeIntervalSince(started)
        return result
    }

    private func textQuery(_ sql: String, rowLimit: Int?) async throws -> QueryResult {
        let rows = try await connection.simpleQuery(sql).get()
        var result = QueryResult()
        guard let first = rows.first else { return result }
        result.columns = first.columnDefinitions.map(\.name)
        result.columnTypes = first.columnDefinitions.map { "\($0.columnType)" }
        let limit = rowLimit ?? Int.max
        result.truncated = rows.count > limit
        result.rows = rows.prefix(limit).map { row in
            row.values.map { value in value.map { String(buffer: $0) } }
        }
        return result
    }

    private var schemaFilter: String {
        database.isEmpty
            ? "NOT IN ('mysql','information_schema','performance_schema','sys')"
            : "= \(dialect.literal(database))"
    }

    func listTables() async throws -> [TableRef] {
        let r = try await execute("""
        SELECT TABLE_SCHEMA, TABLE_NAME, TABLE_TYPE, TABLE_ROWS FROM information_schema.TABLES
        WHERE TABLE_SCHEMA \(schemaFilter) ORDER BY TABLE_SCHEMA, TABLE_NAME
        """, rowLimit: nil)
        return r.rows.map {
            TableRef(schema: $0[0] ?? "", name: $0[1] ?? "", kind: ($0[2] ?? "").contains("VIEW") ? .view : .table,
                     estimatedRows: $0[3].flatMap { Int($0) })
        }
    }

    func listColumns() async throws -> [ColumnBrief] {
        try await execute("""
        SELECT TABLE_SCHEMA, TABLE_NAME, COLUMN_NAME, DATA_TYPE FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA \(schemaFilter) ORDER BY TABLE_SCHEMA, TABLE_NAME, ORDINAL_POSITION
        """, rowLimit: 50_000).rows.map {
            ColumnBrief(schema: $0[0] ?? "", table: $0[1] ?? "", column: $0[2] ?? "", type: $0[3] ?? "")
        }
    }

    func details(of table: TableRef) async throws -> TableDetails {
        let s = dialect.literal(table.schema), t = dialect.literal(table.name)
        var details = TableDetails()
        let fks = try await execute("""
        SELECT CONSTRAINT_NAME, COLUMN_NAME, REFERENCED_TABLE_SCHEMA, REFERENCED_TABLE_NAME, REFERENCED_COLUMN_NAME
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = \(s) AND TABLE_NAME = \(t) AND REFERENCED_TABLE_NAME IS NOT NULL
        ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION
        """, rowLimit: nil).rows
        var refs: [String: String] = [:]
        var grouped: [String: ForeignKeyInfo] = [:]
        var order: [String] = []
        for row in fks {
            let name = row[0] ?? "", column = row[1] ?? "", refTable = "\(row[2] ?? "").\(row[3] ?? "")", refColumn = row[4] ?? ""
            refs[column] = "\(refTable).\(refColumn)"
            if grouped[name] == nil { order.append(name) }
            var fk = grouped[name] ?? ForeignKeyInfo(name: name, columns: [], refTable: refTable, refColumns: [])
            fk.columns.append(column)
            fk.refColumns.append(refColumn)
            grouped[name] = fk
        }
        details.foreignKeys = order.compactMap { grouped[$0] }

        let cols = try await execute("""
        SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, COLUMN_KEY FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = \(s) AND TABLE_NAME = \(t) ORDER BY ORDINAL_POSITION
        """, rowLimit: nil).rows
        details.columns = cols.map {
            ColumnInfo(name: $0[0] ?? "", type: $0[1] ?? "", nullable: $0[2] == "YES", defaultValue: $0[3],
                       isPrimaryKey: $0[4] == "PRI", references: refs[$0[0] ?? ""])
        }

        let idx = try await execute("""
        SELECT INDEX_NAME, NON_UNIQUE, GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX)
        FROM information_schema.STATISTICS WHERE TABLE_SCHEMA = \(s) AND TABLE_NAME = \(t)
        GROUP BY INDEX_NAME, NON_UNIQUE ORDER BY INDEX_NAME = 'PRIMARY' DESC, INDEX_NAME
        """, rowLimit: nil).rows
        details.indexes = idx.map {
            IndexInfo(name: $0[0] ?? "", columns: ($0[2] ?? "").split(separator: ",").map(String.init),
                      unique: $0[1] == "0", primary: $0[0] == "PRIMARY", definition: nil)
        }
        let ddl = try? await execute("SHOW CREATE TABLE \(dialect.qualified(table))", rowLimit: 1)
        details.ddl = ddl?.rows.first.flatMap { $0.count > 1 ? $0[1] : nil }
        return details
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? DBError { return e.localizedDescription }
        if let e = error as? MySQLError { return e.message }
        return String(describing: error)
    }
}
