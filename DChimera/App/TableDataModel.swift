import SwiftUI

struct CellKey: Hashable {
    var row: Int
    var column: Int
}

/// State of one open table: the current page, sort, filter and edits that are not saved yet.
@MainActor
final class TableDataModel: ObservableObject {
    let table: TableRef
    unowned let session: DBSession

    @Published var details: TableDetails?
    @Published var result: QueryResult?
    @Published var page = 0
    @Published var pageSize = 100
    @Published var sort: SortSpec?
    @Published var filterText = ""
    @Published var appliedFilter = ""
    @Published var loading = false
    @Published var error: String?
    @Published var exactCount: Int?
    @Published var counting = false
    @Published var edits: [CellKey: String?] = [:]
    @Published var deleted: Set<Int> = []
    @Published var newRows: [[String?]] = []
    @Published var saving = false
    @Published var loadedAt: Date?
    /// 0 data, 1 structure, 2 DDL.
    @Published var mode = 0

    private(set) var usesRowid = false

    init(table: TableRef, session: DBSession) {
        self.table = table
        self.session = session
    }

    var dialect: SQLDialect { session.config.kind.dialect }

    var keyColumns: [String] {
        if usesRowid { return [SQLDialect.rowidColumn] }
        return details?.primaryKey ?? []
    }

    var canEdit: Bool {
        !session.config.readOnly && table.kind == .table && !keyColumns.isEmpty
    }

    var editHint: String? {
        if session.config.readOnly { return "Read-only connection" }
        if table.kind != .table { return "Views cannot be edited here" }
        if details != nil && keyColumns.isEmpty { return "No primary key — editing is off" }
        return nil
    }

    /// Indices of result columns shown to the user (the helper rowid column is hidden).
    var visibleColumns: [Int] {
        guard let r = result else { return [] }
        return r.columns.indices.filter { r.columns[$0] != SQLDialect.rowidColumn }
    }

    var pendingCount: Int {
        Set(edits.keys.map(\.row)).subtracting(deleted).count + deleted.count + newRows.count
    }

    var totalLabel: String {
        if let exactCount { return Fmt.grouped(exactCount) }
        if let est = table.estimatedRows, est > 0 { return "~" + Fmt.grouped(est) }
        return "?"
    }

    var hasNextPage: Bool {
        guard let r = result else { return false }
        if let exactCount { return (page + 1) * pageSize < exactCount }
        return r.rows.count >= pageSize
    }

    // MARK: Loading

    /// Loads the table's columns, indexes, keys and DDL if they are not loaded yet.
    func loadDetails() async {
        guard details == nil, let driver = session.driver else { return }
        details = try? await driver.details(of: table)
    }

    func loadIfNeeded() async {
        if result == nil && !loading { await reload() }
    }

    func reload() async {
        guard let driver = session.driver else {
            error = "Not connected"
            return
        }
        withAnimation(Theme.spring) { loading = true }
        defer { withAnimation(Theme.spring) { loading = false } }
        do {
            if details == nil {
                details = try await driver.details(of: table)
                if let sqlite = driver as? SQLiteDriver, details?.primaryKey.isEmpty ?? true {
                    usesRowid = await sqlite.hasRowid(table)
                }
            }
            let order = usesRowid ? ["rowid"] : (details?.primaryKey ?? [])
            let sql = dialect.selectPage(table, withRowid: usesRowid, filter: appliedFilter, sort: sort, defaultOrder: order, limit: pageSize, offset: page * pageSize)
            let r = try await driver.execute(sql, rowLimit: pageSize)
            withAnimation(Theme.spring) {
                result = r
                error = nil
                loadedAt = Date()
            }
            if session.config.kind == .sqlite && exactCount == nil {
                await countRows()
            }
        } catch {
            withAnimation(Theme.spring) { self.error = error.localizedDescription }
        }
    }

    func countRows() async {
        guard let driver = session.driver else { return }
        counting = true
        defer { counting = false }
        if let value = try? await driver.execute(dialect.count(table, filter: appliedFilter), rowLimit: 1).rows.first?.first ?? nil,
           let n = Int(value) {
            withAnimation(Theme.spring) { exactCount = n }
        }
    }

    func toggleSort(_ column: String) {
        guard pendingCount == 0 else { return }
        if let s = sort, s.column == column {
            sort = s.ascending ? SortSpec(column: column, ascending: false) : nil
        } else {
            sort = SortSpec(column: column, ascending: true)
        }
        page = 0
        Task { await reload() }
    }

    func applyFilter(_ text: String? = nil) {
        if let text { filterText = text }
        appliedFilter = filterText
        page = 0
        exactCount = nil
        discard()
        Task {
            await reload()
            if session.config.kind != .sqlite, !appliedFilter.isEmpty { await countRows() }
        }
    }

    func go(toPage p: Int) {
        guard p >= 0, p != page else { return }
        discard()
        page = p
        Task { await reload() }
    }

    func setPageSize(_ size: Int) {
        pageSize = size
        page = 0
        discard()
        Task { await reload() }
    }

    // MARK: Editing

    func original(_ key: CellKey) -> String? {
        guard let r = result, key.row < r.rows.count, key.column < r.rows[key.row].count else { return nil }
        return r.rows[key.row][key.column]
    }

    func value(_ key: CellKey) -> String? {
        if let edited = edits[key] { return edited }
        return original(key)
    }

    func setValue(_ value: String?, at key: CellKey) {
        guard canEdit else { return }
        withAnimation(Theme.spring) {
            if value == original(key) {
                edits[key] = nil
            } else {
                edits[key] = .some(value)
            }
        }
    }

    func toggleDelete(row: Int) {
        guard canEdit else { return }
        withAnimation(Theme.spring) {
            if deleted.contains(row) { deleted.remove(row) } else { deleted.insert(row) }
        }
    }

    func addRow() {
        guard canEdit, let r = result else { return }
        withAnimation(Theme.bouncy) { newRows.append(Array(repeating: nil, count: r.columns.count)) }
    }

    func setNewValue(_ value: String?, row: Int, column: Int) {
        guard row < newRows.count, column < newRows[row].count else { return }
        newRows[row][column] = value
    }

    func discard() {
        withAnimation(Theme.spring) {
            edits = [:]
            deleted = []
            newRows = []
        }
    }

    private func keys(for row: Int) -> [(column: String, value: String?)] {
        guard let r = result else { return [] }
        return keyColumns.compactMap { name in
            guard let c = r.columns.firstIndex(of: name), row < r.rows.count else { return nil }
            return (name, r.rows[row][c])
        }
    }

    /// The SQL that Save will send, in order.
    func pendingStatements() -> [String] {
        guard let r = result else { return [] }
        var statements: [String] = []
        let rows = Set(edits.keys.map(\.row)).subtracting(deleted).sorted()
        for row in rows {
            let set = edits.filter { $0.key.row == row }.sorted { $0.key.column < $1.key.column }.map { (r.columns[$0.key.column], $0.value) }
            statements.append(dialect.update(table, set: set, keys: keys(for: row)) + ";")
        }
        for row in deleted.sorted() {
            statements.append(dialect.delete(table, keys: keys(for: row)) + ";")
        }
        for values in newRows {
            let pairs = r.columns.indices.filter { r.columns[$0] != SQLDialect.rowidColumn }.map { (r.columns[$0], values[$0]) }
            statements.append(dialect.insert(table, values: pairs) + ";")
        }
        return statements
    }

    func save() async {
        let statements = pendingStatements()
        guard !statements.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            try await session.runTransaction(statements.map { String($0.dropLast()) })
            let n = statements.count
            discard()
            exactCount = nil
            AppModel.shared.showToast("Saved \(n) change\(n == 1 ? "" : "s")", symbol: "checkmark.circle.fill")
            await reload()
        } catch {
            AppModel.shared.showToast(error.localizedDescription, symbol: "xmark.octagon.fill", isError: true)
        }
    }
}
