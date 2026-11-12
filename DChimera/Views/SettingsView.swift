import SwiftUI

struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage("accentIndex") private var accentIndex = 0
    @AppStorage("rowLimit") private var rowLimit = 1000
    @AppStorage("editorFontSize") private var fontSize = 13.0
    @AppStorage("confirmDangerous") private var confirmDangerous = true
    @AppStorage("skin") private var skinRaw = SkinKind.telegram.rawValue
    @AppStorage("autoCheckUpdates") private var autoCheckUpdates = true
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Form {
            Section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(160), spacing: 14), count: 3), spacing: 16) {
                    ForEach(SkinKind.allCases) { kind in
                        let selected = skinRaw == kind.rawValue
                        VStack(spacing: 6) {
                            SkinPreview(kind: kind, selected: selected)
                                .scaleEffect(selected ? 1.03 : 1)
                            Label(kind.title, systemImage: kind.symbol)
                                .font(.system(size: 12.5, weight: selected ? .bold : .medium))
                            Text(kind.subtitle)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(width: 150)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(Theme.bouncy) { skinRaw = kind.rawValue } }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            Section("Look") {
                Picker("Appearance", selection: $appearance) {
                    ForEach(Appearance.allCases) { a in Label(a.title, systemImage: a.symbol).tag(a) }
                }
                .pickerStyle(.segmented)
                if skinRaw == SkinKind.matrix.rawValue {
                    Text("Matrix always uses phosphor green and a dark window.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                if let kind = SkinKind(rawValue: skinRaw), Skin.make(kind).isScenic {
                    Text("\(kind.title) always uses its own accent and a dark window.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Accent")
                    Spacer()
                    ForEach(Theme.accents.indices, id: \.self) { i in
                        let option = Theme.accents[i]
                        Circle()
                            .fill(LinearGradient(colors: [option.top, option.bottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary.opacity(accentIndex == i ? 0.8 : 0), lineWidth: 2).padding(-4))
                            .scaleEffect(accentIndex == i ? 1.12 : 1)
                            .onTapGesture { withAnimation(Theme.bouncy) { accentIndex = i } }
                            .help(option.name)
                    }
                }
            }
            Section("Console") {
                Picker("Row limit", selection: $rowLimit) {
                    ForEach([100, 500, 1000, 5000, 10000], id: \.self) { Text(Fmt.grouped($0)).tag($0) }
                }
                HStack {
                    Text("Editor font")
                    Slider(value: $fontSize, in: 11...18, step: 1)
                    Text("\(Int(fontSize)) pt").monospacedDigit().frame(width: 40)
                }
                Toggle("Ask before DROP, TRUNCATE, ALTER and DELETE/UPDATE without WHERE", isOn: $confirmDangerous)
            }
            MCPSettingsSection()
            Section("Updates") {
                LabeledContent("Version") {
                    HStack(spacing: 10) {
                        Text(updater.currentVersion).monospacedDigit()
                        if let release = updater.available {
                            Text("\(release.version) available").foregroundStyle(Theme.success)
                        }
                    }
                }
                Toggle("Check for updates when DChimera starts", isOn: $autoCheckUpdates)
                HStack {
                    Button(updater.available == nil ? "Check Now" : "Show Update…") {
                        if updater.available != nil { updater.showDialog = true } else { Task { await updater.check(userInitiated: true) } }
                    }
                    if let checked = updater.lastChecked {
                        Text("Last checked \(Fmt.time(checked))").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Link("Releases on GitHub", destination: Updater.releasesPage).font(.system(size: 11.5))
                }
            }
            Section("Storage") {
                LabeledContent("Connections & history") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.dataDirectory]) }
                }
                Text("Passwords are kept in the macOS Keychain (service “\(Keychain.service)”), never in files.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 860)
    }
}

/// Settings → Claude (MCP): the master switch, which connections Claude sees, and how to connect Claude
/// in read-only or read & write mode.
struct MCPSettingsSection: View {
    @EnvironmentObject private var app: AppModel
    @ObservedObject private var model = MCPSettingsModel.shared
    @State private var copied: String?

    var body: some View {
        Section {
            Toggle("Let Claude use DChimera", isOn: $model.enabled)
            Text(model.enabled
                 ? "You pick the access when you connect Claude: dchimera-read only reads, dchimera-write can also change data and add connections. Register both and turn on the one you need in Claude."
                 : "Claude sees no tools from DChimera until you turn this on.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            if model.enabled {
                connections
            }
            setup
        } header: {
            Text("Claude (MCP)")
        }
    }

    @ViewBuilder
    private var connections: some View {
        if app.connections.isEmpty {
            Text("No connections yet.").foregroundStyle(.secondary)
        } else {
            ForEach(app.sortedConnections) { c in
                Toggle(isOn: access(c.id)) {
                    HStack(spacing: 8) {
                        Text(c.displayName)
                        Tag(text: c.envTag.0, color: c.envTag.1)
                    }
                }
            }
            Text("Read-only (prod) connections start hidden: whatever Claude reads is sent to the model. A read-only connection stays read-only even for dchimera-write.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var setup: some View {
        claudeCode(.readOnly, title: "Claude Code: read only",
                   detail: "list_connections, list_tables, describe_table, query. Every query runs in a read-only transaction.")
        claudeCode(.readWrite, title: "Claude Code: read & write",
                   detail: "Also execute (DROP, TRUNCATE, ALTER and DELETE / UPDATE without WHERE ask you first) and add_connection (you type the password in a DChimera window).")
        LabeledContent("Claude Desktop, Cursor") {
            copyButton("desktop", label: "Copy config", MCPSetup.claudeDesktopJSON)
        }
        Text("Both entries for \"mcpServers\" in the client's config file. Restart the client, then turn on the one you need in its tools menu.")
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func claudeCode(_ mode: MCPMode, title: String, detail: String) -> some View {
        let command = MCPSetup.claudeCodeCommand(mode)
        LabeledContent(title) {
            copyButton(mode.serverName, label: "Copy command", command)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
    }

    private func copyButton(_ what: String, label: String, _ text: String) -> some View {
        Button(copied == what ? "Copied" : label) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = what
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copied == what { copied = nil }
            }
        }
    }

    private func access(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { app.connections.first { $0.id == id }?.mcpVisible ?? false },
            set: { app.setMCPAccess(id, $0) }
        )
    }
}
