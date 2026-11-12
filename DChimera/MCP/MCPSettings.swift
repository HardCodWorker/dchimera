import Combine
import Foundation

/// What one MCP server process may do. It is chosen when the server is registered in Claude:
/// `DChimera --mcp` is read-only, `DChimera --mcp --write` can change data and add connections.
enum MCPMode: String, Sendable {
    case readOnly, readWrite

    static var fromArguments: MCPMode {
        CommandLine.arguments.contains("--write") ? .readWrite : .readOnly
    }

    var serverName: String {
        switch self {
        case .readOnly: "dchimera-read"
        case .readWrite: "dchimera-write"
        }
    }

    var arguments: [String] {
        switch self {
        case .readOnly: ["--mcp"]
        case .readWrite: ["--mcp", "--write"]
        }
    }
}

/// MCP settings live in a small file next to connections.json, not in UserDefaults:
/// the MCP server is a separate process and must see a change made in Settings right away.
struct MCPConfig: Codable, Equatable, Sendable {
    /// The master switch in Settings. Off: every server shows no tools.
    var enabled = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled) {
            self.enabled = enabled
        } else {
            // The first version stored a mode: "off", "readOnly" or "readWrite".
            let legacy = try? c.decodeIfPresent(String.self, forKey: .mode)
            enabled = legacy != "off"
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enabled, forKey: .enabled)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, mode
    }
}

enum MCPConfigStore {
    static var file: URL { AppPaths.dataDirectory.appendingPathComponent("mcp.json") }

    static func load() -> MCPConfig {
        guard let data = try? Data(contentsOf: file) else { return MCPConfig() }
        return (try? JSONDecoder().decode(MCPConfig.self, from: data)) ?? MCPConfig()
    }

    static func save(_ config: MCPConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(config) else { return }
        try? data.write(to: file, options: .atomic)
    }
}

/// The master switch as Settings shows it; every change is written to mcp.json for the running MCP servers.
@MainActor
final class MCPSettingsModel: ObservableObject {
    static let shared = MCPSettingsModel()

    @Published var enabled: Bool {
        didSet {
            guard enabled != oldValue else { return }
            var config = MCPConfigStore.load()
            config.enabled = enabled
            MCPConfigStore.save(config)
        }
    }

    private init() {
        enabled = MCPConfigStore.load().enabled
    }
}

extension ConnectionConfig {
    /// Whether Claude sees this connection. Read-only (prod) connections are hidden until you allow them:
    /// whatever Claude reads is sent to the model.
    var mcpVisible: Bool { mcpAccess ?? !readOnly }
}

/// Connections are written by the app and by the MCP server (add_connection).
/// The server posts this after a change so a running app reloads connections.json.
enum ConnectionsChanged {
    static let name = Notification.Name("dev.dchimera.connectionsChanged")

    static func post() {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: AppPaths.dataDirectory.path, userInfo: nil, deliverImmediately: true)
    }
}

/// The commands that register DChimera in Claude Code, and the same for Claude Desktop's config file.
enum MCPSetup {
    static var executable: String {
        Bundle.main.executablePath ?? "/Applications/DChimera.app/Contents/MacOS/DChimera"
    }

    static func claudeCodeCommand(_ mode: MCPMode) -> String {
        "claude mcp add --scope user \(mode.serverName) -- \(shellQuoted(executable)) \(mode.arguments.joined(separator: " "))"
    }

    static var claudeDesktopJSON: String {
        let path = executable.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        func entry(_ mode: MCPMode) -> String {
            let args = mode.arguments.map { "\"\($0)\"" }.joined(separator: ", ")
            return """
            "\(mode.serverName)": {
              "command": "\(path)",
              "args": [\(args)]
            }
            """
        }
        return entry(.readOnly) + ",\n" + entry(.readWrite)
    }

    private static func shellQuoted(_ s: String) -> String {
        guard s.contains(where: { " '\"\\$`!&;()<>|*?[]{}".contains($0) }) else { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
