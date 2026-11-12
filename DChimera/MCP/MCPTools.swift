import Foundation

struct MCPOutcome: Sendable {
    var text: String
    var isError = false
}

/// The tools DChimera offers over MCP. Connections and settings are read from disk on every call,
/// so changes made in the app apply at once. Passwords come from the Keychain and never leave this process.
actor MCPTools {
    private struct Open {
        var signature: String
        var driver: any DatabaseDriver
    }

    private var open: [String: Open] = [:]
    let mode: MCPMode

    init(mode: MCPMode) {
        self.mode = mode
    }

    static let defaultRows = 200
    static let maxCell = 2000

    /// Where to send Claude when a tool needs the other mode.
    static let writeHint = "Changes need the read & write server (dchimera-write); the user picks it when connecting Claude."

    static func instructions(for mode: MCPMode) -> String {
        var text = """
        DChimera gives you the databases the user saved in the DChimera app (PostgreSQL, MySQL, SQLite). \
        Start with list_connections, then list_tables and describe_table before writing SQL. \
        query runs one read-only statement in a read-only transaction. \
        Never ask the user for passwords: DChimera takes them from the macOS Keychain.
        """
        if mode == .readWrite {
            text += """
             This is the read & write server. execute runs statements that change data or structure; \
            DROP, TRUNCATE, ALTER and DELETE / UPDATE without WHERE show the user a confirmation window first. \
            add_connection saves a new connection; DChimera asks the user for its password in its own window.
            """
        } else {
            text += " This is the read-only server: nothing can be changed. " + writeHint
        }
        return text
    }

    // MARK: Definitions

    static func definitions(for mode: MCPMode) -> [[String: Any]] {
        let connection: [String: Any] = ["type": "string", "description": "Connection name or id from list_connections."]
        let maxRows: [String: Any] = [
            "type": "integer", "minimum": 1,
            "description": "Most rows to return (default \(defaultRows), capped by the row limit in DChimera settings).",
        ]
        var tools: [[String: Any]] = [
            [
                "name": "list_connections",
                "title": "List connections",
                "description": "Lists the database connections the user allowed for Claude in DChimera: name, id, database type, environment (local / dev / prod), whether the connection is read-only, and the current access mode.",
                "inputSchema": ["type": "object", "properties": [String: Any]()],
                "annotations": ["readOnlyHint": true, "openWorldHint": false],
            ],
            [
                "name": "list_tables",
                "title": "List tables",
                "description": "Lists tables, views and materialized views of a connection with estimated row counts.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": connection,
                        "schema": ["type": "string", "description": "Only this schema (optional)."],
                    ],
                    "required": ["connection"],
                ],
                "annotations": ["readOnlyHint": true, "openWorldHint": false],
            ],
            [
                "name": "describe_table",
                "title": "Describe table",
                "description": "Columns (type, nullable, default, primary key, references), indexes, foreign keys and the CREATE statement of one table.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": connection,
                        "table": ["type": "string", "description": "Table name, optionally with schema: \"public.users\" or \"users\"."],
                    ],
                    "required": ["connection", "table"],
                ],
                "annotations": ["readOnlyHint": true, "openWorldHint": false],
            ],
            [
                "name": "query",
                "title": "Run read-only query",
                "description": "Runs one read-only statement (SELECT, WITH, VALUES, TABLE, SHOW, EXPLAIN, DESCRIBE, PRAGMA) in a read-only transaction and returns columns and rows as JSON. Cannot change anything.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": connection,
                        "sql": ["type": "string", "description": "One SQL statement."],
                        "max_rows": maxRows,
                    ],
                    "required": ["connection", "sql"],
                ],
                "annotations": ["readOnlyHint": true, "openWorldHint": false],
            ],
        ]
        if mode == .readWrite {
            tools.append([
                "name": "execute",
                "title": "Execute SQL (changes data)",
                "description": "Runs SQL that may change data or structure: INSERT, UPDATE, DELETE, CREATE, ALTER, DROP, BEGIN / COMMIT and so on. Several statements separated by ; run in order on one connection and stop at the first error. DROP, TRUNCATE, ALTER and DELETE / UPDATE without WHERE open a confirmation window for the user first.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "connection": connection,
                        "sql": ["type": "string", "description": "One or more SQL statements."],
                        "max_rows": maxRows,
                    ],
                    "required": ["connection", "sql"],
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false],
            ])
            tools.append([
                "name": "add_connection",
                "title": "Add connection",
                "description": "Saves a new database connection in DChimera after checking that it connects. Never pass a password: for PostgreSQL and MySQL DChimera opens a window where the user types it, and keeps it in the Keychain. Claude can use the new connection right away.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Name shown in DChimera."],
                        "type": ["type": "string", "enum": ["postgres", "mysql", "sqlite"]],
                        "host": ["type": "string", "description": "PostgreSQL / MySQL host (default localhost)."],
                        "port": ["type": "integer", "description": "Default 5432 for PostgreSQL, 3306 for MySQL."],
                        "database": ["type": "string"],
                        "user": ["type": "string"],
                        "ssl_mode": ["type": "string", "enum": ["disable", "prefer", "require", "verify"], "description": "Default prefer."],
                        "file_path": ["type": "string", "description": "SQLite file (must exist)."],
                        "read_only": ["type": "boolean", "description": "Open it read-only (shown as prod in DChimera). Default false."],
                    ],
                    "required": ["name", "type"],
                ],
                "annotations": ["readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false],
            ])
        }
        return tools
    }

    // MARK: Calls

    func call(_ name: String, arguments: [String: Any]) async -> MCPOutcome {
        guard MCPConfigStore.load().enabled else {
            return MCPOutcome(text: "Claude access is turned off in DChimera → Settings → Claude (MCP).", isError: true)
        }
        do {
            switch name {
            case "list_connections":
                return listConnections(mode: mode)
            case "list_tables":
                return try await listTables(arguments)
            case "describe_table":
                return try await describeTable(arguments)
            case "query":
                return try await query(arguments, mode: mode)
            case "execute":
                guard mode == .readWrite else { return MCPOutcome(text: "execute is not available here. " + Self.writeHint, isError: true) }
                return try await execute(arguments)
            case "add_connection":
                guard mode == .readWrite else { return MCPOutcome(text: "add_connection is not available here. " + Self.writeHint, isError: true) }
                return try await addConnection(arguments)
            default:
                return MCPOutcome(text: "Unknown tool: \(name)", isError: true)
            }
        } catch {
            return MCPOutcome(text: error.localizedDescription, isError: true)
        }
    }

    func closeAll() async {
        for item in open.values { await item.driver.close() }
        open.removeAll()
    }

    // MARK: Tools

    private func listConnections(mode: MCPMode) -> MCPOutcome {
        let all = ConnectionStore.load()
        let visible = all.filter(\.mcpVisible)
        let list: [[String: Any]] = visible.map { c in
            [
                "name": c.displayName,
                "id": c.id.uuidString,
                "type": c.kind.title,
                "environment": c.envName,
                "read_only": c.readOnly,
                "target": c.subtitle,
            ]
        }
        var out: [String: Any] = [
            "access": mode == .readWrite ? "read and write (query, execute, add_connection)" : "read only (query)",
            "connections": list,
        ]
        let hidden = all.count - visible.count
        if hidden > 0 {
            let what = hidden == 1 ? "1 more connection is hidden from Claude; the user can allow it" : "\(hidden) more connections are hidden from Claude; the user can allow them"
            out["hidden"] = what + " in DChimera → Settings → Claude (MCP)."
        }
        if all.isEmpty {
            out["hint"] = "No connections are saved in DChimera yet."
        }
        return MCPOutcome(text: Self.json(out))
    }

    private func listTables(_ arguments: [String: Any]) async throws -> MCPOutcome {
        let config = try resolve(arguments)
        let driver = try await driver(for: config, readOnly: true)
        var tables = try await driver.listTables()
        if let schema = (arguments["schema"] as? String)?.trimmingCharacters(in: .whitespaces), !schema.isEmpty {
            tables = tables.filter { $0.schema.caseInsensitiveCompare(schema) == .orderedSame }
        }
        let list: [[String: Any]] = tables.map { t in
            var item: [String: Any] = ["name": Self.name(of: t, dialect: driver.dialect), "kind": Self.kind(t.kind)]
            if let rows = t.estimatedRows { item["estimated_rows"] = rows }
            return item
        }
        return MCPOutcome(text: Self.json(["connection": config.displayName, "tables": list]))
    }

    private func describeTable(_ arguments: [String: Any]) async throws -> MCPOutcome {
        let config = try resolve(arguments)
        guard let wanted = (arguments["table"] as? String)?.trimmingCharacters(in: .whitespaces), !wanted.isEmpty else {
            throw DBError.message("table is required.")
        }
        let driver = try await driver(for: config, readOnly: true)
        let tables = try await driver.listTables()
        let parts = Self.splitName(wanted)
        let matches = tables.filter { (t: TableRef) -> Bool in
            guard t.name.caseInsensitiveCompare(parts.name) == .orderedSame else { return false }
            guard let schema = parts.schema else { return true }
            return t.schema.caseInsensitiveCompare(schema) == .orderedSame
        }
        guard !matches.isEmpty else {
            throw DBError.message("No table “\(wanted)” in \(config.displayName). Call list_tables to see the names.")
        }
        guard matches.count == 1 else {
            let names = matches.map { Self.name(of: $0, dialect: driver.dialect) }.joined(separator: ", ")
            throw DBError.message("“\(wanted)” is in several schemas: \(names). Add the schema.")
        }
        let table = matches[0]
        let details = try await driver.details(of: table)
        var out: [String: Any] = [
            "table": Self.name(of: table, dialect: driver.dialect),
            "kind": Self.kind(table.kind),
            "columns": details.columns.map { c -> [String: Any] in
                var item: [String: Any] = ["name": c.name, "type": c.type, "nullable": c.nullable]
                if c.isPrimaryKey { item["primary_key"] = true }
                if let d = c.defaultValue { item["default"] = d }
                if let r = c.references { item["references"] = r }
                return item
            },
        ]
        if let rows = table.estimatedRows { out["estimated_rows"] = rows }
        if !details.indexes.isEmpty {
            out["indexes"] = details.indexes.map { i -> [String: Any] in
                var item: [String: Any] = ["name": i.name, "columns": i.columns, "unique": i.unique]
                if i.primary { item["primary"] = true }
                return item
            }
        }
        if !details.foreignKeys.isEmpty {
            out["foreign_keys"] = details.foreignKeys.map { f -> [String: Any] in
                ["name": f.name, "columns": f.columns, "references": "\(f.refTable)(\(f.refColumns.joined(separator: ", ")))"]
            }
        }
        if let ddl = details.ddl { out["ddl"] = ddl }
        return MCPOutcome(text: Self.json(out))
    }

    private func query(_ arguments: [String: Any], mode: MCPMode) async throws -> MCPOutcome {
        let config = try resolve(arguments)
        let statements = SQLText.statements(try Self.sql(arguments))
        guard statements.count == 1 else {
            throw DBError.message("query runs exactly one statement, this has \(statements.count). Send them one by one.")
        }
        let statement = statements[0]
        guard SQLText.returnsRows(statement) else {
            let next = mode == .readWrite ? "Use the execute tool to change data." : Self.writeHint
            throw DBError.message("query is read-only and takes SELECT, WITH, VALUES, TABLE, SHOW, EXPLAIN, DESCRIBE or PRAGMA. \(next)")
        }
        let maxRows = Self.maxRows(arguments)
        let driver = try await driver(for: config, readOnly: true)
        do {
            let result = try await Self.readOnly(statement, maxRows: maxRows, on: driver)
            return MCPOutcome(text: Self.json(Self.describe(result)))
        } catch {
            await dropIfBroken(config, readOnly: true)
            throw error
        }
    }

    private func execute(_ arguments: [String: Any]) async throws -> MCPOutcome {
        let config = try resolve(arguments)
        let statements = SQLText.statements(try Self.sql(arguments))
        guard !statements.isEmpty else { throw DBError.message("sql is empty.") }
        if AppSettings.confirmDangerous {
            var reasons: [String] = []
            for s in statements {
                if let r = SQLText.dangerReason(s), !reasons.contains(r) { reasons.append(r) }
            }
            if !reasons.isEmpty {
                let sql = statements.joined(separator: ";\n")
                guard MCPConfirm.ask(connection: config.displayName, reasons: reasons, sql: sql) else {
                    throw DBError.message("The user declined this in DChimera's confirmation window. Nothing was run.")
                }
            }
        }
        let maxRows = Self.maxRows(arguments)
        let driver = try await driver(for: config, readOnly: config.readOnly)
        var done: [[String: Any]] = []
        for (i, statement) in statements.enumerated() {
            do {
                let result = try await driver.execute(statement, rowLimit: maxRows)
                var item = Self.describe(result)
                if statements.count > 1 { item["statement"] = i + 1 }
                done.append(item)
            } catch {
                await dropIfBroken(config, readOnly: config.readOnly)
                var message = error.localizedDescription
                if config.readOnly {
                    message += " (“\(config.displayName)” is a read-only connection in DChimera, so the server rejects changes.)"
                }
                if statements.count == 1 { throw DBError.message(message) }
                let out: [String: Any] = ["failed_statement": i + 1, "error": message, "completed": done]
                return MCPOutcome(text: Self.json(out), isError: true)
            }
        }
        if done.count == 1 { return MCPOutcome(text: Self.json(done[0])) }
        return MCPOutcome(text: Self.json(["statements": done]))
    }

    private func addConnection(_ arguments: [String: Any]) async throws -> MCPOutcome {
        func text(_ key: String) -> String? {
            guard let v = (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
            return v
        }
        guard let name = text("name") else { throw DBError.message("name is required.") }
        guard let kind = text("type").flatMap({ DBKind(rawValue: $0.lowercased()) }) else {
            throw DBError.message("type must be postgres, mysql or sqlite.")
        }
        var all = ConnectionStore.load()
        if all.contains(where: { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }) {
            throw DBError.message("A connection named “\(name)” already exists. Pick another name.")
        }

        var config = ConnectionConfig()
        config.name = name
        config.kind = kind
        config.readOnly = arguments["read_only"] as? Bool ?? false
        config.mcpAccess = true
        config.colorIndex = (all.map(\.colorIndex).max() ?? -1) + 1
        if kind == .sqlite {
            guard let path = text("file_path") else { throw DBError.message("file_path is required for SQLite.") }
            config.filePath = (path as NSString).expandingTildeInPath
            config.port = 0
        } else {
            config.host = text("host") ?? "localhost"
            config.port = (arguments["port"] as? NSNumber)?.intValue ?? kind.defaultPort
            config.database = text("database") ?? ""
            config.user = text("user") ?? ""
            switch text("ssl_mode")?.lowercased() {
            case nil, "prefer": config.sslMode = .prefer
            case "disable", "off": config.sslMode = .disable
            case "require": config.sslMode = .require
            case "verify", "verify-full", "verifyfull": config.sslMode = .verifyFull
            case let other?: throw DBError.message("ssl_mode “\(other)” is not one of disable, prefer, require, verify.")
            }
        }

        var password: String?
        if kind != .sqlite {
            guard let typed = MCPConfirm.askPassword(connection: name, target: "\(kind.title) · \(config.subtitle)") else {
                throw DBError.message("The user cancelled the password window. Nothing was saved.")
            }
            password = typed.isEmpty ? nil : typed
        }

        let version: String
        do {
            let driver = try await DriverFactory.connect(config, password: password)
            version = (try? await driver.serverVersion()) ?? ""
            await driver.close()
        } catch {
            throw DBError.message("Could not connect, nothing was saved: \(error.localizedDescription)")
        }

        if let password { Keychain.setPassword(password, for: config.id) }
        all = ConnectionStore.load()
        all.append(config)
        ConnectionStore.save(all)
        ConnectionsChanged.post()
        var out: [String: Any] = [
            "added": config.displayName,
            "id": config.id.uuidString,
            "type": kind.title,
            "environment": config.envName,
            "target": config.subtitle,
        ]
        if !version.isEmpty { out["server_version"] = version }
        return MCPOutcome(text: Self.json(out))
    }

    // MARK: Connections

    private func resolve(_ arguments: [String: Any]) throws -> ConnectionConfig {
        guard let ref = (arguments["connection"] as? String)?.trimmingCharacters(in: .whitespaces), !ref.isEmpty else {
            throw DBError.message("connection is required. Call list_connections to see the names.")
        }
        let all = ConnectionStore.load()
        let visible = all.filter(\.mcpVisible)
        if let byID = visible.first(where: { $0.id.uuidString.caseInsensitiveCompare(ref) == .orderedSame }) {
            return byID
        }
        let named = visible.filter { $0.displayName.caseInsensitiveCompare(ref) == .orderedSame }
        if named.count == 1 { return named[0] }
        if named.count > 1 {
            throw DBError.message("Several connections are named “\(ref)”. Use the id: \(named.map(\.id.uuidString).joined(separator: ", ")).")
        }
        if all.contains(where: { !$0.mcpVisible && ($0.displayName.caseInsensitiveCompare(ref) == .orderedSame || $0.id.uuidString.caseInsensitiveCompare(ref) == .orderedSame) }) {
            throw DBError.message("“\(ref)” is hidden from Claude. The user can allow it in DChimera → Settings → Claude (MCP).")
        }
        let names = visible.map(\.displayName).joined(separator: ", ")
        throw DBError.message("No connection “\(ref)”. Available: \(names.isEmpty ? "none" : names).")
    }

    /// One open driver per connection and access kind. Reopened when the connection was edited in the app.
    private func driver(for config: ConnectionConfig, readOnly: Bool) async throws -> any DatabaseDriver {
        var config = config
        if readOnly { config.readOnly = true }
        let key = Self.key(config.id, readOnly: readOnly)
        let signature = [config.kind.rawValue, config.host, "\(config.port)", config.database, config.user,
                         config.sslMode.rawValue, config.filePath, "\(config.readOnly)"].joined(separator: "|")
        if let existing = open[key] {
            if existing.signature == signature { return existing.driver }
            await existing.driver.close()
            open[key] = nil
        }
        let password = config.kind == .sqlite ? nil : Keychain.password(for: config.id)
        let driver = try await DriverFactory.connect(config, password: password)
        open[key] = Open(signature: signature, driver: driver)
        return driver
    }

    /// After an error, keep the connection only if it still answers.
    private func dropIfBroken(_ config: ConnectionConfig, readOnly: Bool) async {
        let key = Self.key(config.id, readOnly: readOnly)
        guard let existing = open[key] else { return }
        if (try? await existing.driver.execute("SELECT 1", rowLimit: 1)) == nil {
            await existing.driver.close()
            open[key] = nil
        }
    }

    private static func key(_ id: UUID, readOnly: Bool) -> String {
        id.uuidString + (readOnly ? "/ro" : "/rw")
    }

    // MARK: Read-only execution

    /// The connection is already opened read-only (PostgreSQL default_transaction_read_only, MySQL session
    /// READ ONLY, SQLite read-only file). PostgreSQL also gets an explicit read-only transaction that is
    /// always rolled back, so a SELECT cannot switch the session back to read-write.
    static func readOnly(_ statement: String, maxRows: Int, on driver: any DatabaseDriver) async throws -> QueryResult {
        let postgres = driver.dialect == .postgres
        func attempt(_ sql: String) async throws -> QueryResult {
            if postgres { _ = try await driver.execute("BEGIN READ ONLY", rowLimit: nil) }
            do {
                let result = try await driver.execute(sql, rowLimit: maxRows)
                if postgres { _ = try? await driver.execute("ROLLBACK", rowLimit: nil) }
                return result
            } catch {
                if postgres { _ = try? await driver.execute("ROLLBACK", rowLimit: nil) }
                throw error
            }
        }
        // Like the app: wrap a SELECT so the server sends at most max_rows + 1 rows; fall back to the plain statement.
        if let wrapped = SQLText.limited(statement, limit: maxRows), let result = try? await attempt(wrapped) {
            return result
        }
        return try await attempt(statement)
    }

    // MARK: Formatting

    private static func sql(_ arguments: [String: Any]) throws -> String {
        guard let sql = arguments["sql"] as? String, !SQLText.isBlank(sql) else { throw DBError.message("sql is required.") }
        return sql
    }

    private static func maxRows(_ arguments: [String: Any]) -> Int {
        let asked = (arguments["max_rows"] as? NSNumber)?.intValue ?? defaultRows
        return min(max(asked, 1), AppSettings.rowLimit)
    }

    static func describe(_ result: QueryResult) -> [String: Any] {
        var out: [String: Any] = ["time_ms": Int((result.duration * 1000).rounded())]
        if result.isRowSet {
            out["columns"] = result.columns
            out["rows"] = result.rows.map { row in
                row.map { cell -> Any in
                    guard let cell else { return NSNull() }
                    return cell.count > maxCell ? String(cell.prefix(maxCell)) + "…[\(cell.count) chars]" : cell
                }
            }
            out["row_count"] = result.rows.count
            if result.truncated { out["truncated"] = "more rows exist; raise max_rows or narrow the query" }
        }
        if let m = result.message, !m.isEmpty { out["message"] = m }
        if let n = result.affectedRows { out["affected_rows"] = n }
        if !result.isRowSet && result.message == nil && result.affectedRows == nil { out["message"] = "OK" }
        return out
    }

    private static func name(of table: TableRef, dialect: SQLDialect) -> String {
        dialect == .sqlite && table.schema == "main" ? table.name : "\(table.schema).\(table.name)"
    }

    private static func kind(_ kind: TableRef.Kind) -> String {
        switch kind {
        case .table: "table"
        case .view: "view"
        case .materializedView: "materialized view"
        }
    }

    /// "schema.table", "table", or quoted parts: "\"my schema\".\"my.table\"".
    static func splitName(_ text: String) -> (schema: String?, name: String) {
        var parts: [String] = []
        var current = ""
        var quoted = false
        for ch in text {
            if ch == "\"" || ch == "`" { quoted.toggle(); continue }
            if ch == ".", !quoted { parts.append(current); current = ""; continue }
            current.append(ch)
        }
        parts.append(current)
        if parts.count >= 2 { return (parts[parts.count - 2], parts[parts.count - 1]) }
        return (nil, parts[0])
    }

    static func json(_ object: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            return "{}"
        }
        return String(decoding: data, as: UTF8.self)
    }
}
