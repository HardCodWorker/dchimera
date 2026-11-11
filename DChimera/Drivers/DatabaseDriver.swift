import Foundation

/// One open connection to one database. Every driver is an actor, so calls are serialized.
protocol DatabaseDriver: AnyObject, Sendable {
    var dialect: SQLDialect { get }
    func serverVersion() async throws -> String
    /// Runs one statement. `rowLimit` stops reading rows after that many (the result is marked truncated).
    func execute(_ sql: String, rowLimit: Int?) async throws -> QueryResult
    func listTables() async throws -> [TableRef]
    func listColumns() async throws -> [ColumnBrief]
    func details(of table: TableRef) async throws -> TableDetails
    func close() async
}

enum DriverFactory {
    static func connect(_ config: ConnectionConfig, password: String?) async throws -> any DatabaseDriver {
        switch config.kind {
        case .sqlite:
            return try SQLiteDriver(path: config.filePath, readOnly: config.readOnly)
        case .postgres:
            return try await PostgresDriver.connect(config, password: password)
        case .mysql:
            return try await MySQLDriver.connect(config, password: password)
        }
    }
}

extension DatabaseDriver {
    /// Runs a query and returns the first column of every row.
    func strings(_ sql: String) async throws -> [String] {
        try await execute(sql, rowLimit: nil).rows.compactMap { $0.first ?? nil }
    }
}
