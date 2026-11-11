import AppKit
import SwiftUI

enum SidebarFolder: String, CaseIterable, Identifiable {
    case all, postgres, mysql, sqlite

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .postgres: "Postgres"
        case .mysql: "MySQL"
        case .sqlite: "SQLite"
        }
    }

    func matches(_ kind: DBKind) -> Bool {
        switch self {
        case .all: true
        case .postgres: kind == .postgres
        case .mysql: kind == .mysql
        case .sqlite: kind == .sqlite
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var symbol: String
    var isError = false
}

/// A statement that needs a "yes" before it runs.
struct DangerRequest: Identifiable {
    let id = UUID()
    var sql: String
    var reason: String
    var connectionName: String
    var resume: (Bool) -> Void
}

struct EditorRequest: Identifiable {
    let id = UUID()
    var config: ConnectionConfig
    var isNew: Bool
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var connections: [ConnectionConfig] = []
    @Published private(set) var sessions: [UUID: DBSession] = [:]
    @Published var openID: UUID?
    @Published var search = ""
    @Published var folder: SidebarFolder = .all
    @Published var editor: EditorRequest?
    @Published var quickSwitcher = false
    @Published var toast: Toast?
    @Published var danger: DangerRequest?
    let chrome = WindowChrome()

    private var toastTask: Task<Void, Never>?

    init() {
        Self.migrateSettingsFromBaza()
        connections = ConnectionStore.load()
        for c in connections { sessions[c.id] = DBSession(config: c) }
    }

    /// Copies the settings of the app's earlier name (Baza, bundle dev.baza.app) once.
    private static func migrateSettingsFromBaza() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "migratedFromBaza") == nil else { return }
        defaults.set(true, forKey: "migratedFromBaza")
        guard let old = UserDefaults(suiteName: "dev.baza.app") else { return }
        for key in ["accentIndex", "appearance", "rowLimit", "editorFontSize", "confirmDangerous", "skin"] {
            if defaults.object(forKey: key) == nil, let value = old.object(forKey: key) {
                defaults.set(value, forKey: key)
            }
        }
    }

    // MARK: Lists

    var sortedConnections: [ConnectionConfig] {
        connections.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            let da = a.lastUsedAt ?? a.createdAt, db = b.lastUsedAt ?? b.createdAt
            return da > db
        }
    }

    var visibleConnections: [ConnectionConfig] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return sortedConnections.filter { c in
            guard folder.matches(c.kind) else { return false }
            guard !q.isEmpty else { return true }
            return [c.displayName, c.subtitle, c.kind.title].contains { $0.lowercased().contains(q) }
        }
    }

    func count(in folder: SidebarFolder) -> Int {
        connections.filter { folder.matches($0.kind) }.count
    }

    func session(_ id: UUID) -> DBSession? { sessions[id] }

    var openSession: DBSession? { openID.flatMap { sessions[$0] } }

    // MARK: Navigation

    func open(_ id: UUID) {
        guard let session = sessions[id] else { return }
        withAnimation(Theme.softSpring) { openID = id }
        session.unread = 0
        if session.status == .idle || session.isFailed {
            Task { await session.connect() }
        }
        touch(id)
    }

    func closeConnectionView() {
        withAnimation(Theme.softSpring) { openID = nil }
    }

    func openTable(_ table: TableRef, in id: UUID) {
        open(id)
        sessions[id]?.openTableTab(table)
    }

    // MARK: Editing connections

    func newConnection(kind: DBKind = .postgres) {
        var c = ConnectionConfig()
        c.kind = kind
        c.port = kind.defaultPort
        c.colorIndex = (connections.map(\.colorIndex).max() ?? -1) + 1
        editor = EditorRequest(config: c, isNew: true)
    }

    func edit(_ id: UUID) {
        guard let c = connections.first(where: { $0.id == id }) else { return }
        editor = EditorRequest(config: c, isNew: false)
    }

    /// Saves a connection. `password == nil` keeps whatever is in the Keychain.
    func upsert(_ config: ConnectionConfig, password: String?) {
        if let password, config.kind != .sqlite {
            if password.isEmpty { Keychain.deletePassword(for: config.id) } else { Keychain.setPassword(password, for: config.id) }
        }
        withAnimation(Theme.spring) {
            if let i = connections.firstIndex(where: { $0.id == config.id }) {
                let old = connections[i]
                connections[i] = config
                if let s = sessions[config.id] {
                    s.config = config
                    let endpointChanged = old.host != config.host || old.port != config.port || old.database != config.database
                        || old.user != config.user || old.filePath != config.filePath || old.sslMode != config.sslMode
                        || old.readOnly != config.readOnly || old.kind != config.kind || password != nil
                    if endpointChanged, s.status != .idle {
                        Task { await s.reconnect() }
                    }
                }
            } else {
                connections.append(config)
                sessions[config.id] = DBSession(config: config)
            }
        }
        ConnectionStore.save(connections)
    }

    func delete(_ id: UUID) {
        let session = sessions[id]
        withAnimation(Theme.spring) {
            if openID == id { openID = nil }
            connections.removeAll { $0.id == id }
            sessions[id] = nil
        }
        Task { await session?.disconnect() }
        Keychain.deletePassword(for: id)
        HistoryStore.delete(id)
        ConnectionStore.save(connections)
        showToast("Connection deleted", symbol: "trash")
    }

    func duplicate(_ id: UUID) {
        guard var c = connections.first(where: { $0.id == id }) else { return }
        let oldID = c.id
        c.id = UUID()
        c.name = c.displayName + " copy"
        c.pinned = false
        c.createdAt = Date()
        c.lastUsedAt = nil
        c.colorIndex += 1
        let password = Keychain.password(for: oldID)
        upsert(c, password: password)
    }

    func togglePin(_ id: UUID) {
        guard let i = connections.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(Theme.spring) { connections[i].pinned.toggle() }
        sessions[id]?.config = connections[i]
        ConnectionStore.save(connections)
    }

    func touch(_ id: UUID, preview: String? = nil) {
        guard let i = connections.firstIndex(where: { $0.id == id }) else { return }
        connections[i].lastUsedAt = Date()
        if let preview { connections[i].lastPreview = SQLText.preview(preview) }
        sessions[id]?.config = connections[i]
        ConnectionStore.save(connections)
    }

    // MARK: Demo

    func addDemoDatabase() {
        Task {
            do {
                let url = AppPaths.demoDatabase
                if !FileManager.default.fileExists(atPath: url.path) {
                    try await DemoDatabase.create(at: url)
                }
                var c = ConnectionConfig()
                c.kind = .sqlite
                c.name = "Demo Shop"
                c.filePath = url.path
                c.port = 0
                c.colorIndex = 4
                upsert(c, password: nil)
                showToast("Demo database added", symbol: "sparkles")
                open(c.id)
            } catch {
                showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill", isError: true)
            }
        }
    }

    // MARK: Toasts & confirmations

    func showToast(_ text: String, symbol: String = "checkmark.circle.fill", isError: Bool = false) {
        toastTask?.cancel()
        withAnimation(Theme.bouncy) { toast = Toast(text: text, symbol: symbol, isError: isError) }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(Theme.spring) { self?.toast = nil }
        }
    }

    func confirmDanger(sql: String, reason: String, connection: String) async -> Bool {
        await withCheckedContinuation { continuation in
            withAnimation(Theme.bouncy) {
                danger = DangerRequest(sql: sql, reason: reason, connectionName: connection) { ok in
                    continuation.resume(returning: ok)
                }
            }
        }
    }

    func resolveDanger(_ ok: Bool) {
        guard let request = danger else { return }
        withAnimation(Theme.spring) { danger = nil }
        request.resume(ok)
    }

    func applyAppearance(_ appearance: Appearance) {
        NSApp.appearance = Skin.current.forcesDark ? NSAppearance(named: .darkAqua) : appearance.nsAppearance
    }
}
