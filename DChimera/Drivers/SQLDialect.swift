import Foundation

/// SQL text that differs between databases: quoting and the queries the table browser sends.
enum SQLDialect: Sendable {
    case postgres, mysql, sqlite

    func ident(_ name: String) -> String {
        switch self {
        case .mysql: "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
        default: "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
    }

    func literal(_ value: String?) -> String {
        guard let value else { return "NULL" }
        var s = value.replacingOccurrences(of: "'", with: "''")
        if self == .mysql { s = s.replacingOccurrences(of: "\\", with: "\\\\") }
        return "'" + s + "'"
    }

    func qualified(_ table: TableRef) -> String {
        if self == .sqlite && table.schema == "main" { return ident(table.name) }
        return ident(table.schema) + "." + ident(table.name)
    }

    /// Key values used in WHERE of UPDATE/DELETE. The SQLite rowid is an integer and is written unquoted.
    func keyCondition(_ keys: [(column: String, value: String?)]) -> String {
        keys.map { key in
            if key.column == SQLDialect.rowidColumn, let v = key.value, Int64(v) != nil {
                return "rowid = \(v)"
            }
            guard let v = key.value else { return "\(ident(key.column)) IS NULL" }
            return "\(ident(key.column)) = \(literal(v))"
        }.joined(separator: " AND ")
    }

    static let rowidColumn = "__dchimera_rowid"

    /// `defaultOrder` (primary key columns, or "rowid") keeps pages stable when the user did not pick a sort.
    func selectPage(_ table: TableRef, withRowid: Bool, filter: String, sort: SortSpec?, defaultOrder: [String] = [], limit: Int, offset: Int) -> String {
        var sql = withRowid ? "SELECT rowid AS \(ident(SQLDialect.rowidColumn)), * FROM \(qualified(table))" : "SELECT * FROM \(qualified(table))"
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !f.isEmpty { sql += " WHERE \(f)" }
        if let sort {
            sql += " ORDER BY \(ident(sort.column)) \(sort.ascending ? "ASC" : "DESC")"
        } else if !defaultOrder.isEmpty {
            sql += " ORDER BY " + defaultOrder.map { $0 == "rowid" ? "rowid" : ident($0) }.joined(separator: ", ")
        }
        sql += " LIMIT \(limit) OFFSET \(offset)"
        return sql
    }

    func count(_ table: TableRef, filter: String) -> String {
        var sql = "SELECT count(*) FROM \(qualified(table))"
        let f = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !f.isEmpty { sql += " WHERE \(f)" }
        return sql
    }

    func update(_ table: TableRef, set: [(column: String, value: String?)], keys: [(column: String, value: String?)]) -> String {
        let assignments = set.map { "\(ident($0.column)) = \(literal($0.value))" }.joined(separator: ", ")
        return "UPDATE \(qualified(table)) SET \(assignments) WHERE \(keyCondition(keys))"
    }

    func delete(_ table: TableRef, keys: [(column: String, value: String?)]) -> String {
        "DELETE FROM \(qualified(table)) WHERE \(keyCondition(keys))"
    }

    func insert(_ table: TableRef, values: [(column: String, value: String?)]) -> String {
        let filled = values.filter { $0.value != nil }
        if filled.isEmpty {
            return self == .mysql ? "INSERT INTO \(qualified(table)) () VALUES ()" : "INSERT INTO \(qualified(table)) DEFAULT VALUES"
        }
        let cols = filled.map { ident($0.column) }.joined(separator: ", ")
        let vals = filled.map { literal($0.value) }.joined(separator: ", ")
        return "INSERT INTO \(qualified(table)) (\(cols)) VALUES (\(vals))"
    }

    var beginTransaction: String { self == .mysql ? "START TRANSACTION" : "BEGIN" }
}
