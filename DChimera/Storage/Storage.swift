import Foundation
import Security

/// Where DChimera keeps its JSON files. Passwords never go here — they live in the Keychain.
enum AppPaths {
    static var dataDirectory: URL = {
        if let custom = ProcessInfo.processInfo.environment["DCHIMERA_DATA_DIR"], !custom.isEmpty {
            let url = URL(fileURLWithPath: custom, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("DChimera", isDirectory: true)
        // The app used to be called Baza: move its folder (connections, history, demo db) once.
        let old = base.appendingPathComponent("Baza", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: old.path) {
            try? FileManager.default.moveItem(at: old, to: url)
        }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var connectionsFile: URL { dataDirectory.appendingPathComponent("connections.json") }
    static var historyDirectory: URL {
        let url = dataDirectory.appendingPathComponent("history", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var demoDatabase: URL { dataDirectory.appendingPathComponent("demo-shop.sqlite") }
}

enum ConnectionStore {
    static func load() -> [ConnectionConfig] {
        guard let data = try? Data(contentsOf: AppPaths.connectionsFile) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([ConnectionConfig].self, from: data)) ?? []
    }

    static func save(_ connections: [ConnectionConfig]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(connections) else { return }
        try? data.write(to: AppPaths.connectionsFile, options: .atomic)
    }
}

enum HistoryStore {
    private static func file(_ id: UUID) -> URL {
        AppPaths.historyDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    static func load(_ id: UUID) -> [HistoryItem] {
        guard let data = try? Data(contentsOf: file(id)) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([HistoryItem].self, from: data)) ?? []
    }

    static func save(_ items: [HistoryItem], for id: UUID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(Array(items.suffix(500))) else { return }
        try? data.write(to: file(id), options: .atomic)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: file(id))
    }
}

/// Connection passwords in the login Keychain (generic password, one item per connection id).
enum Keychain {
    /// Kept from the app's first name (Baza) so passwords saved back then keep working.
    static var service: String {
        ProcessInfo.processInfo.environment["DCHIMERA_DATA_DIR"] == nil ? "dev.baza.app.connection" : "dev.baza.app.connection.test"
    }

    private static func query(_ id: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
        ]
    }

    @discardableResult
    static func setPassword(_ password: String, for id: UUID) -> Bool {
        let data = Data(password.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var add = query(id)
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "DChimera database password"
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func password(for id: UUID) -> String? {
        var q = query(id)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func hasPassword(for id: UUID) -> Bool {
        var q = query(id)
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func deletePassword(for id: UUID) {
        SecItemDelete(query(id) as CFDictionary)
    }
}
