import Foundation
import SwiftUI

// MARK: - Connection

enum DBKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case postgres, mysql, sqlite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .postgres: "PostgreSQL"
        case .mysql: "MySQL"
        case .sqlite: "SQLite"
        }
    }

    var shortTitle: String {
        switch self {
        case .postgres: "PG"
        case .mysql: "MY"
        case .sqlite: "SQ"
        }
    }

    var defaultPort: Int {
        switch self {
        case .postgres: 5432
        case .mysql: 3306
        case .sqlite: 0
        }
    }

    var symbol: String {
        switch self {
        case .postgres: "cylinder.split.1x2.fill"
        case .mysql: "cylinder.fill"
        case .sqlite: "internaldrive.fill"
        }
    }

    var dialect: SQLDialect {
        switch self {
        case .postgres: .postgres
        case .mysql: .mysql
        case .sqlite: .sqlite
        }
    }
}

enum SSLMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case disable, prefer, require, verifyFull

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disable: "Off"
        case .prefer: "Prefer"
        case .require: "Require"
        case .verifyFull: "Verify"
        }
    }

    var hint: String {
        switch self {
        case .disable: "Plain TCP, no encryption"
        case .prefer: "TLS if the server offers it, no certificate check"
        case .require: "TLS required, certificate is not checked"
        case .verifyFull: "TLS required, certificate and host name are checked"
        }
    }
}

struct ConnectionConfig: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name = ""
    var kind: DBKind = .postgres
    var host = "localhost"
    var port = 5432
    var database = ""
    var user = ""
    var sslMode: SSLMode = .prefer
    var filePath = ""
    var colorIndex = 0
    var readOnly = false
    var pinned = false
    var createdAt = Date()
    var lastUsedAt: Date?
    var lastPreview: String?
    /// Claude (MCP) access; nil means the default: on, except for read-only (prod) connections.
    var mcpAccess: Bool?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(DBKind.self, forKey: .kind) ?? .postgres
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? "localhost"
        port = try c.decodeIfPresent(Int.self, forKey: .port) ?? kind.defaultPort
        database = try c.decodeIfPresent(String.self, forKey: .database) ?? ""
        user = try c.decodeIfPresent(String.self, forKey: .user) ?? ""
        sslMode = try c.decodeIfPresent(SSLMode.self, forKey: .sslMode) ?? .prefer
        filePath = try c.decodeIfPresent(String.self, forKey: .filePath) ?? ""
        colorIndex = try c.decodeIfPresent(Int.self, forKey: .colorIndex) ?? 0
        readOnly = try c.decodeIfPresent(Bool.self, forKey: .readOnly) ?? false
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastUsedAt = try c.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        lastPreview = try c.decodeIfPresent(String.self, forKey: .lastPreview)
        mcpAccess = try c.decodeIfPresent(Bool.self, forKey: .mcpAccess)
    }

    var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if kind == .sqlite { return (filePath as NSString).lastPathComponent }
        return database.isEmpty ? host : database
    }

    var subtitle: String {
        if kind == .sqlite { return (filePath as NSString).abbreviatingWithTildeInPath }
        let who = user.isEmpty ? "" : "\(user)@"
        let db = database.isEmpty ? "" : "/\(database)"
        return "\(who)\(host):\(port)\(db)"
    }

    var initials: String {
        let words = displayName
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(separator: " ")
            .filter { !$0.isEmpty }
        let letters = words.prefix(2).compactMap { $0.first.map(String.init) }
        let joined = letters.joined().uppercased()
        return joined.isEmpty ? "DB" : joined
    }

    /// The environment tag: read-only connections count as prod, local hosts and SQLite files as local.
    var envName: String {
        if readOnly { return "prod" }
        if kind == .sqlite || ["localhost", "127.0.0.1", "::1"].contains(host) { return "local" }
        return "dev"
    }
}

// MARK: - Schema

struct TableRef: Identifiable, Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable {
        case table, view, materializedView
    }

    var schema: String
    var name: String
    var kind: Kind = .table
    var estimatedRows: Int?

    var id: String { "\(schema).\(name)" }

    static func == (lhs: TableRef, rhs: TableRef) -> Bool {
        lhs.schema == rhs.schema && lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(schema)
        hasher.combine(name)
    }

    var symbol: String {
        switch kind {
        case .table: "tablecells"
        case .view: "eye"
        case .materializedView: "square.stack.3d.up"
        }
    }
}

struct ColumnInfo: Identifiable, Hashable, Sendable {
    var name: String
    var type: String
    var nullable: Bool
    var defaultValue: String?
    var isPrimaryKey: Bool
    var references: String?

    var id: String { name }
}

struct IndexInfo: Identifiable, Hashable, Sendable {
    var name: String
    var columns: [String]
    var unique: Bool
    var primary: Bool
    var definition: String?

    var id: String { name }
}

struct ForeignKeyInfo: Identifiable, Hashable, Sendable {
    var name: String
    var columns: [String]
    var refTable: String
    var refColumns: [String]

    var id: String { name + columns.joined(separator: ",") }
}

struct TableDetails: Sendable {
    var columns: [ColumnInfo] = []
    var indexes: [IndexInfo] = []
    var foreignKeys: [ForeignKeyInfo] = []
    var ddl: String?

    var primaryKey: [String] { columns.filter(\.isPrimaryKey).map(\.name) }
}

/// One column of one table, used by SQL autocomplete.
struct ColumnBrief: Hashable, Sendable {
    var schema: String
    var table: String
    var column: String
    var type: String
}

// MARK: - Results

struct QueryResult: Sendable {
    var columns: [String] = []
    var columnTypes: [String] = []
    var rows: [[String?]] = []
    var affectedRows: Int?
    var message: String?
    var truncated = false
    var duration: TimeInterval = 0

    var isRowSet: Bool { !columns.isEmpty }

    /// Columns whose non-null values all look numeric are right-aligned in grids.
    func numericColumns() -> Set<Int> {
        var result = Set<Int>()
        let sample = rows.prefix(60)
        for c in columns.indices {
            let type = c < columnTypes.count ? columnTypes[c].lowercased() : ""
            if ["int", "float", "double", "numeric", "decimal", "real", "serial", "money", "bigint", "smallint"].contains(where: type.contains) {
                result.insert(c)
                continue
            }
            if type.isEmpty || type == "?" {
                var any = false
                var allNumeric = true
                for row in sample {
                    guard c < row.count, let v = row[c] else { continue }
                    any = true
                    if Double(v) == nil { allNumeric = false; break }
                }
                if any && allNumeric { result.insert(c) }
            }
        }
        return result
    }
}

struct SortSpec: Equatable, Sendable {
    var column: String
    var ascending: Bool
}

// MARK: - Console

struct Exchange: Identifiable {
    enum State {
        case running
        case success(QueryResult)
        case failure(String)
    }

    let id = UUID()
    var sql: String
    var startedAt = Date()
    var finishedAt: Date?
    var state: State = .running
    var limit: Int?
    var starred = false

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }
}

struct ConsoleNote: Identifiable {
    let id = UUID()
    var text: String
    var symbol: String
    var date = Date()
    var isError = false
    /// Set for the output of a backslash command (\\dt, \\d …): `text` is then the printed output.
    var command: String?
}

enum ConsoleItem: Identifiable {
    case note(ConsoleNote)
    case exchange(Exchange)

    var id: UUID {
        switch self {
        case .note(let n): n.id
        case .exchange(let e): e.id
        }
    }

    var date: Date {
        switch self {
        case .note(let n): n.date
        case .exchange(let e): e.startedAt
        }
    }
}

struct HistoryItem: Codable, Identifiable, Hashable {
    var id = UUID()
    var sql: String
    var date = Date()
    var success = true
    var duration: TimeInterval = 0
    var rowCount: Int?
    var starred = false
}

enum DBError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let m): m
        }
    }
}

// MARK: - Workspace tabs (Wet Asphalt theme)

struct WorkTab: Identifiable, Equatable {
    enum Kind: Equatable {
        case table(TableRef)
        case query(UUID)
    }

    let id = UUID()
    var kind: Kind

    var table: TableRef? {
        if case .table(let t) = kind { return t }
        return nil
    }
}

/// One SQL editor tab with its last result.
@MainActor
final class QueryTab: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var text: String
    /// A new result clears the header sort.
    @Published var result: QueryResult? {
        didSet {
            sort = nil
            sortedRows = nil
        }
    }
    @Published var error: String?
    @Published var messages: [String] = []
    @Published var running = false
    /// Header sort of the loaded rows (LocalSort); the result itself keeps the server's order.
    @Published private(set) var sort: SortSpec?
    @Published private(set) var sortedRows: [[String?]]?

    init(title: String, text: String) {
        self.title = title
        self.text = text
    }

    /// Rows in the order the grid shows them.
    var shownRows: [[String?]] { sortedRows ?? result?.rows ?? [] }

    /// The result as shown, for copy and export.
    var shownResult: QueryResult? {
        guard var r = result else { return nil }
        if let sortedRows { r.rows = sortedRows }
        return r
    }

    func toggleSort(_ column: String) {
        guard let r = result else { return }
        let next = LocalSort.next(sort, column)
        sortedRows = next == nil ? nil : LocalSort.sorted(r.rows, columns: r.columns, by: next)
        sort = next
    }
}
