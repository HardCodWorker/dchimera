import SwiftUI

/// Everything about one saved connection while the app runs: the driver, the schema,
/// the console conversation and the open tables.
@MainActor
final class DBSession: ObservableObject, Identifiable {
    enum Status: Equatable {
        case idle, connecting, connected, failed(String)
    }

    enum Topic: Hashable {
        case console, saved, history, table(TableRef)
    }

    let id: UUID
    @Published var config: ConnectionConfig
    @Published var status: Status = .idle
    @Published var serverVersion = ""
    @Published var connectMs: Int?
    @Published var tables: [TableRef] = []
    @Published var columns: [ColumnBrief] = []
    @Published var loadingSchema = false
    @Published var collapsedSchemas: Set<String> = []
    @Published var topic: Topic = .console
    @Published var items: [ConsoleItem] = []
    @Published var composer = ""
    @Published var history: [HistoryItem]
    @Published var unread = 0
    @Published var showInfo = false
    @Published var tableSearch = ""
    @Published var runningCount = 0
    let editor = EditorController()

    private(set) var driver: (any DatabaseDriver)?
    private var tableModels: [TableRef: TableDataModel] = [:]
    private var connectTask: Task<Void, Never>?

    init(config: ConnectionConfig) {
        id = config.id
        self.config = config
        history = HistoryStore.load(config.id)
    }

    var isConnected: Bool { status == .connected }
    var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    var statusLine: String {
        switch status {
        case .idle: return "not connected"
        case .connecting: return "connecting…"
        case .connected:
            let n = tables.count
            return "\(serverVersion.isEmpty ? "connected" : serverVersion) · \(n) table\(n == 1 ? "" : "s")"
        case .failed(let m): return m.split(separator: "\n").first.map(String.init) ?? m
        }
    }

    var schemas: [String] {
        var seen = Set<String>()
        return tables.compactMap { seen.insert($0.schema).inserted ? $0.schema : nil }
    }

    func tables(in schema: String) -> [TableRef] {
        let q = tableSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return tables.filter { $0.schema == schema && (q.isEmpty || $0.name.lowercased().contains(q)) }
    }

    var starred: [HistoryItem] { history.filter(\.starred).reversed() }

    // MARK: Connection

    func connect() async {
        guard status != .connecting, status != .connected else { return }
        withAnimation(Theme.spring) { status = .connecting }
        let password = config.kind == .sqlite ? nil : Keychain.password(for: id)
        let started = Date()
        do {
            let d = try await DriverFactory.connect(config, password: password)
            driver = d
            serverVersion = (try? await d.serverVersion()) ?? config.kind.title
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            connectMs = ms
            withAnimation(Theme.bouncy) { status = .connected }
            var note = "Connected · \(serverVersion) · \(ms) ms"
            if config.readOnly { note += " · read-only" }
            addNote(note, symbol: "bolt.fill")
            await reloadSchema()
        } catch {
            let message = error.localizedDescription
            withAnimation(Theme.spring) { status = .failed(message) }
            addNote("Connection failed: \(message)", symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    func disconnect() async {
        let d = driver
        driver = nil
        tableModels = [:]
        withAnimation(Theme.spring) {
            status = .idle
            if case .table = topic { topic = .console }
        }
        await d?.close()
    }

    func reconnect() async {
        await disconnect()
        await connect()
    }

    func reloadSchema() async {
        guard let driver else { return }
        loadingSchema = true
        defer { loadingSchema = false }
        do {
            let list = try await driver.listTables()
            withAnimation(Theme.spring) { tables = list }
            columns = (try? await driver.listColumns()) ?? []
        } catch {
            addNote("Could not read the schema: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill", isError: true)
        }
    }

    // MARK: Topics

    func select(_ newTopic: Topic) {
        withAnimation(Theme.spring) { topic = newTopic }
        if newTopic == .console { unread = 0 }
    }

    func model(for table: TableRef) -> TableDataModel {
        if let m = tableModels[table] { return m }
        let m = TableDataModel(table: table, session: self)
        tableModels[table] = m
        return m
    }

    func toggleSchema(_ schema: String) {
        withAnimation(Theme.spring) {
            if collapsedSchemas.contains(schema) { collapsedSchemas.remove(schema) } else { collapsedSchemas.insert(schema) }
        }
    }

    /// True when every schema group is folded.
    var allSchemasCollapsed: Bool {
        let all = schemas
        return !all.isEmpty && all.allSatisfy(collapsedSchemas.contains)
    }

    /// One button for all groups: folds every schema, or opens all of them when everything is already folded.
    func toggleAllSchemas() {
        withAnimation(Theme.spring) {
            collapsedSchemas = allSchemasCollapsed ? [] : Set(schemas)
        }
    }

    // MARK: Console

    func addNote(_ text: String, symbol: String, isError: Bool = false) {
        withAnimation(Theme.bouncy) {
            items.append(.note(ConsoleNote(text: text, symbol: symbol, isError: isError)))
        }
    }

    /// psql-style backslash commands. Returns false when `input` is not one.
    func runMeta(_ input: String) async -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("\\") else { return false }
        let parts = trimmed.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0].lowercased()
        let arg = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        var out = ""
        var isError = false
        switch command {
        case "\\clear":
            clearConsole()
            return true
        case "\\help", "\\?":
            out = [
                "\\dt [text]     list tables (optionally only names containing text)",
                "\\d  name       columns, indexes and keys of a table",
                "\\conninfo      where you are connected",
                "\\clear         clear the screen",
                "\\help          this list",
                "",
                "⌘↩ run statement · ⇧⌘↩ run all · ↑ previous query · ⌘K jump anywhere",
            ].joined(separator: "\n")
        case "\\dt":
            let list = tables.filter { arg.isEmpty || $0.name.localizedCaseInsensitiveContains(arg) }
            var r = QueryResult()
            r.columns = ["schema", "name", "type", "rows"]
            r.columnTypes = ["text", "text", "text", "int8"]
            r.rows = list.map { [$0.schema, $0.name, $0.kind == .table ? "table" : ($0.kind == .view ? "view" : "matview"), $0.estimatedRows.map(String.init)] }
            out = TerminalFormat.table(r, maxRows: 1000) + "\n(\(list.count) row\(list.count == 1 ? "" : "s"))"
        case "\\d":
            let wanted = arg.lowercased()
            guard !wanted.isEmpty, let table = tables.first(where: { $0.name.lowercased() == wanted || "\($0.schema).\($0.name)".lowercased() == wanted }) else {
                out = arg.isEmpty ? "usage: \\d table_name" : "Did not find any relation named \"\(arg)\"."
                isError = !arg.isEmpty
                break
            }
            guard let driver else { out = "not connected"; isError = true; break }
            do {
                let d = try await driver.details(of: table)
                var r = QueryResult()
                r.columns = ["Column", "Type", "Nullable", "Default"]
                r.rows = d.columns.map { [$0.name + ($0.isPrimaryKey ? " 🔑" : ""), $0.type, $0.nullable ? "" : "not null", $0.defaultValue] }
                var lines = ["Table \"\(table.schema).\(table.name)\"", TerminalFormat.table(r, maxRows: 1000)]
                if !d.indexes.isEmpty {
                    lines.append("Indexes:")
                    lines += d.indexes.map { "    \"\($0.name)\"\($0.primary ? " PRIMARY KEY" : ($0.unique ? " UNIQUE" : "")) (\($0.columns.joined(separator: ", ")))" }
                }
                if !d.foreignKeys.isEmpty {
                    lines.append("Foreign-key constraints:")
                    lines += d.foreignKeys.map { "    \"\($0.name)\" FOREIGN KEY (\($0.columns.joined(separator: ", "))) REFERENCES \($0.refTable)(\($0.refColumns.joined(separator: ", ")))" }
                }
                out = lines.joined(separator: "\n")
            } catch {
                out = error.localizedDescription
                isError = true
            }
        case "\\conninfo":
            if config.kind == .sqlite {
                out = "You are connected to SQLite file \"\(config.filePath)\"\(config.readOnly ? " (read-only)" : "")."
            } else {
                out = "You are connected to database \"\(config.database)\" as user \"\(config.user)\" on host \"\(config.host)\" at port \"\(config.port)\"\(config.readOnly ? " (read-only)" : "")."
            }
        default:
            out = "invalid command \(command)\nTry \\help for help."
            isError = true
        }
        withAnimation(Theme.spring) {
            items.append(.note(ConsoleNote(text: out, symbol: "terminal", isError: isError, command: trimmed)))
        }
        return true
    }

    /// Sends the composer text: every statement becomes its own query bubble.
    func send(_ sql: String) {
        let statements = SQLText.statements(sql)
        guard !statements.isEmpty else { return }
        Task {
            for statement in statements {
                let ok = await run(statement)
                if !ok { break }
            }
        }
    }

    /// Runs one statement as a chat exchange. Returns false when it failed or was cancelled.
    @discardableResult
    func run(_ statement: String) async -> Bool {
        if AppSettings.confirmDangerous, let reason = SQLText.dangerReason(statement) {
            let ok = await AppModel.shared.confirmDanger(sql: statement, reason: reason, connection: config.displayName)
            if !ok {
                addNote("Cancelled — nothing was sent", symbol: "hand.raised.fill")
                return false
            }
        }
        var exchange = Exchange(sql: statement)
        exchange.limit = AppSettings.rowLimit
        let exchangeID = exchange.id
        withAnimation(Theme.bouncy) { items.append(.exchange(exchange)) }
        let outcome = await perform(statement)
        switch outcome {
        case .success(let result): finish(exchangeID, state: .success(result))
        case .failure(let message): finish(exchangeID, state: .failure(message))
        }
        if topic != .console || AppModel.shared.openID != id {
            withAnimation(Theme.bouncy) { unread += 1 }
        }
        if case .success = outcome { return true }
        return false
    }

    enum Outcome {
        case success(QueryResult)
        case failure(String)
    }

    /// Runs one statement on the server (connecting first if needed), applies the row limit,
    /// records history and reloads the schema after DDL. Shared by every theme's editor.
    func perform(_ statement: String) async -> Outcome {
        if status != .connected {
            await connect()
        }
        guard let driver else { return .failure("Not connected") }
        let limit = AppSettings.rowLimit
        runningCount += 1
        defer { runningCount -= 1 }
        do {
            var result: QueryResult
            if let wrapped = SQLText.limited(statement, limit: limit) {
                do {
                    result = try await driver.execute(wrapped, rowLimit: limit)
                } catch {
                    result = try await driver.execute(statement, rowLimit: limit)
                }
            } else {
                result = try await driver.execute(statement, rowLimit: limit)
            }
            recordHistory(statement, success: true, duration: result.duration, rows: result.isRowSet ? result.rows.count : result.affectedRows)
            if ["create", "drop", "alter", "rename"].contains(SQLText.firstKeyword(statement)) {
                await reloadSchema()
            }
            AppModel.shared.touch(id, preview: statement)
            return .success(result)
        } catch {
            recordHistory(statement, success: false, duration: 0, rows: nil)
            AppModel.shared.touch(id, preview: statement)
            return .failure(error.localizedDescription)
        }
    }

    /// Same as `perform`, but asks first for dangerous statements. Returns nil when the user said no.
    func performConfirmed(_ statement: String) async -> Outcome? {
        if AppSettings.confirmDangerous, let reason = SQLText.dangerReason(statement) {
            let ok = await AppModel.shared.confirmDanger(sql: statement, reason: reason, connection: config.displayName)
            if !ok { return nil }
        }
        return await perform(statement)
    }

    /// ⌘↩ / ⇧⌘↩ from the menu: runs the active SQL tab (or opens one).
    func runFromComposer(all: Bool) {
        if case .query(let qid) = activeTab?.kind, let query = queryTab(qid) {
            runQueryTab(query, all: all)
        }
    }

    // MARK: Workspace tabs

    @Published var tabs: [WorkTab] = []
    @Published var activeTabID: UUID?
    private(set) var queryTabs: [UUID: QueryTab] = [:]
    private var queryCounter = 0

    var activeTab: WorkTab? { tabs.first { $0.id == activeTabID } }

    func openTableTab(_ table: TableRef) {
        if let existing = tabs.first(where: { $0.table == table }) {
            activeTabID = existing.id
            return
        }
        let tab = WorkTab(kind: .table(table))
        tabs.append(tab)
        activeTabID = tab.id
    }

    @discardableResult
    func newQueryTab(text: String = "") -> QueryTab {
        queryCounter += 1
        let query = QueryTab(title: "SQL Query \(queryCounter)", text: text)
        queryTabs[query.id] = query
        let tab = WorkTab(kind: .query(query.id))
        tabs.append(tab)
        activeTabID = tab.id
        return query
    }

    func queryTab(_ id: UUID) -> QueryTab? { queryTabs[id] }

    func closeTab(_ id: UUID) {
        guard let i = tabs.firstIndex(where: { $0.id == id }) else { return }
        if case .query(let qid) = tabs[i].kind { queryTabs[qid] = nil }
        tabs.remove(at: i)
        if activeTabID == id {
            activeTabID = tabs.indices.contains(i) ? tabs[i].id : tabs.last?.id
        }
    }

    /// Runs the statement under the cursor (or everything) of a query tab.
    func runQueryTab(_ query: QueryTab, all: Bool) {
        let text: String
        if all {
            text = query.text
        } else {
            text = editor.currentStatement() ?? query.text
        }
        let statements = SQLText.statements(text)
        guard !statements.isEmpty else { return }
        query.running = true
        query.error = nil
        Task {
            var last: QueryResult?
            var messages: [String] = []
            for statement in statements {
                guard let outcome = await performConfirmed(statement) else {
                    messages.append("Cancelled: \(SQLText.preview(statement))")
                    break
                }
                switch outcome {
                case .success(let r):
                    if r.isRowSet { last = r }
                    messages.append(r.isRowSet ? "\(r.rows.count) rows · \(Fmt.duration(r.duration))"
                                               : "\(r.message ?? "OK") \(r.affectedRows.map { "· \($0) rows affected" } ?? "") · \(Fmt.duration(r.duration))")
                case .failure(let m):
                    query.error = m
                    messages.append("Error: \(m)")
                }
                if query.error != nil { break }
            }
            if let last { query.result = last }
            query.messages = messages
            query.running = false
        }
    }

    private func finish(_ id: UUID, state: Exchange.State) {
        guard let i = items.firstIndex(where: { $0.id == id }), case .exchange(var e) = items[i] else { return }
        e.state = state
        e.finishedAt = Date()
        withAnimation(Theme.bouncy) { items[i] = .exchange(e) }
    }

    func rerun(_ exchangeID: UUID) {
        guard let e = exchange(exchangeID) else { return }
        Task { await run(e.sql) }
    }

    func exchange(_ id: UUID) -> Exchange? {
        for item in items {
            if case .exchange(let e) = item, e.id == id { return e }
        }
        return nil
    }

    func toggleStar(_ exchangeID: UUID) {
        guard let i = items.firstIndex(where: { $0.id == exchangeID }), case .exchange(var e) = items[i] else { return }
        e.starred.toggle()
        withAnimation(Theme.bouncy) { items[i] = .exchange(e) }
        setStar(sql: e.sql, starred: e.starred)
        AppModel.shared.showToast(e.starred ? "Saved to Saved queries" : "Removed from Saved queries", symbol: e.starred ? "star.fill" : "star.slash")
    }

    func setStar(sql: String, starred: Bool) {
        if let j = history.lastIndex(where: { $0.sql == sql }) {
            history[j].starred = starred
        } else if starred {
            history.append(HistoryItem(sql: sql, starred: true))
        }
        HistoryStore.save(history, for: id)
    }

    func removeItem(_ itemID: UUID) {
        withAnimation(Theme.spring) { items.removeAll { $0.id == itemID } }
    }

    func clearConsole() {
        withAnimation(Theme.spring) { items.removeAll() }
    }

    private func recordHistory(_ sql: String, success: Bool, duration: TimeInterval, rows: Int?) {
        let starred = history.last(where: { $0.sql == sql })?.starred ?? false
        history.removeAll { $0.sql == sql && !$0.starred }
        history.append(HistoryItem(sql: sql, success: success, duration: duration, rowCount: rows, starred: starred))
        if starred { history.removeAll { $0.sql == sql && $0.id != history.last?.id } }
        HistoryStore.save(history, for: id)
    }

    func clearHistory() {
        history.removeAll { !$0.starred }
        HistoryStore.save(history, for: id)
    }

    /// Runs statements for the table editor inside one transaction.
    func runTransaction(_ statements: [String]) async throws {
        guard let driver else { throw DBError.message("Not connected") }
        _ = try await driver.execute(driver.dialect.beginTransaction, rowLimit: nil)
        do {
            for s in statements { _ = try await driver.execute(s, rowLimit: nil) }
            _ = try await driver.execute("COMMIT", rowLimit: nil)
        } catch {
            _ = try? await driver.execute("ROLLBACK", rowLimit: nil)
            throw error
        }
        for s in statements { recordHistory(s, success: true, duration: 0, rows: nil) }
    }
}
