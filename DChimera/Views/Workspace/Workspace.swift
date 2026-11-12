import SwiftUI
import UniformTypeIdentifiers

// The Wet Asphalt theme: a table-first workspace (toolbar, item list, tabs, filter bar,
// data/structure switch, SQL tabs, row details) on Liquid Glass panels.

struct WorkspaceRoot: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        ZStack {
            if let session = app.openSession {
                WorkspaceView(session: session)
                    .id(session.id)
                    .transition(.opacity)
            } else {
                WelcomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: app.openID)
    }
}

// MARK: - Shared bits

struct Tag: View {
    let text: String
    var color: Color = Theme.secondaryText

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .heavy))
            .tracking(0.4)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.16)))
    }
}

/// Small flat toolbar button.
struct ToolButton: View {
    let symbol: String
    var title: String?
    var help: String = ""
    var active = false
    var glass = true
    let action: () -> Void
    @State private var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12.5, weight: .medium))
                if let title { Text(title).font(.system(size: 12, weight: .medium)) }
            }
            .foregroundStyle(active ? Theme.onAccent : Theme.text)
            .padding(.horizontal, title == nil ? 8 : 11)
            .frame(height: 28)
            .frame(minWidth: 28)
            .contentShape(Capsule())
            .if(glass) {
                $0.liquidGlass(SkinShape.capsule, tint: active ? palette.accent : nil, clear: !active, interactive: true, rim: hover ? 0.45 : 0.15)
            }
            .if(!glass) { $0.background(Capsule().fill(hover ? Theme.hover : .clear)) }
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { h in withAnimation(.easeOut(duration: 0.15)) { hover = h } }
    }
}

extension View {
    /// System glass button style on macOS 26, bordered before; the theme's own buttons in the painted themes.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if Skin.current.isScenic {
            self.buttonStyle(SkinButtonStyle(prominent: prominent))
        } else if #available(macOS 26.0, *), !GlassFallback.forced {
            if prominent { self.buttonStyle(.glassProminent) } else { self.buttonStyle(.glass) }
        } else {
            if prominent { self.buttonStyle(.borderedProminent) } else { self.buttonStyle(.bordered) }
        }
    }
}

extension ConnectionConfig {
    /// Environment tag shown in the workspace (TablePlus-like colored labels).
    var envTag: (String, Color) {
        switch envName {
        case "prod": ("prod", Color(hex: 0xE5534B))
        case "local": ("local", Color(hex: 0x3CC47C))
        default: ("dev", Color(hex: 0x5EA2F0))
        }
    }
}

// MARK: - Welcome (connection manager)

struct WelcomeView: View {
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var chrome: WindowChrome
    @ObservedObject private var updater = Updater.shared
    @State private var selection: UUID?
    @State private var query = ""
    @State private var confirmDelete: UUID?
    @Environment(\.palette) private var palette

    private var list: [ConnectionConfig] {
        app.sortedConnections.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.subtitle.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 104, height: 104)
                Text("DChimera").font(.system(size: 24, weight: .bold))
                Text("Version \(updater.currentVersion)").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                Spacer().frame(height: 6)
                VStack(spacing: 8) {
                    WelcomeAction(symbol: "plus.circle", title: "Create a new connection…") { app.newConnection() }
                    WelcomeAction(symbol: "doc.badge.plus", title: "Open a SQLite file…") { app.newConnection(kind: .sqlite) }
                    WelcomeAction(symbol: "sparkles", title: "Add the demo database") { app.addDemoDatabase() }
                    if let release = updater.available {
                        WelcomeAction(symbol: "arrow.down.circle.fill", title: "Update to \(release.version)…", highlighted: true) {
                            updater.showDialog = true
                        }
                    } else {
                        WelcomeAction(symbol: "arrow.triangle.2.circlepath", title: "Check for updates…") {
                            Task { await updater.check(userInitiated: true) }
                        }
                    }
                }
                Spacer()
                Text("⌘K open anything · ⌃⌘T switch theme")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(24)
            .frame(width: 300)
            .glassSurface(SkinShape(radius: 22))

            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiaryText)
                    TextField("Search for connection…", text: $query).textFieldStyle(.plain)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.field))
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(list) { c in
                            WelcomeRow(config: c, selected: selection == c.id)
                                .onTapGesture(count: 2) { app.open(c.id) }
                                .simultaneousGesture(TapGesture().onEnded { selection = c.id })
                                .contextMenu {
                                    Button("Connect") { app.open(c.id) }
                                    Button("Edit…") { app.edit(c.id) }
                                    Button("Duplicate") { app.duplicate(c.id) }
                                    Divider()
                                    Button("Delete…", role: .destructive) { confirmDelete = c.id }
                                }
                        }
                        if list.isEmpty {
                            Text(app.connections.isEmpty ? "No connections yet" : "Nothing found")
                                .foregroundStyle(Theme.tertiaryText)
                                .padding(30)
                        }
                    }
                }
                HStack {
                    Text("\(app.connections.count) connection\(app.connections.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                    Spacer()
                    Button("Connect") { if let selection { app.open(selection) } }
                        .glassButton(prominent: true)
                        .keyboardShortcut(.defaultAction)
                        .disabled(selection == nil)
                }
            }
            .padding(16)
        }
        .frame(maxWidth: 900, maxHeight: 560)
        .glassSurface(SkinShape(radius: 26))
        .padding(.top, chrome.topInset)
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Delete this connection?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Delete", role: .destructive) { if let id = confirmDelete { app.delete(id) } }
        }
        .onAppear { selection = selection ?? list.first?.id }
    }
}

struct WelcomeAction: View {
    let symbol: String
    let title: String
    var highlighted = false
    let action: () -> Void
    @State private var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 14)).foregroundStyle(highlighted ? Theme.onAccent : palette.accent).frame(width: 18)
                Text(title).font(.system(size: 12.5, weight: highlighted ? .semibold : .medium))
                Spacer()
            }
            .foregroundStyle(highlighted ? Theme.onAccent : Theme.text)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .contentShape(Capsule())
            .liquidGlass(SkinShape.capsule, tint: highlighted ? palette.accent : nil, clear: !highlighted, interactive: true, rim: hover ? 0.45 : 0.15)
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct WelcomeRow: View {
    let config: ConnectionConfig
    let selected: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        let tag = config.envTag
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(tag.1.opacity(0.18))
                Image(systemName: config.kind.symbol).foregroundStyle(tag.1)
            }
            .frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(config.displayName).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(selected && Skin.current.isScenic ? Theme.onAccent : Theme.text)
                    Tag(text: tag.0, color: selected && Skin.current.isScenic ? Theme.onAccent : tag.1)
                }
                Text("\(config.kind.title) · \(config.subtitle)")
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.8) : Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Text(Fmt.listDate(config.lastUsedAt)).font(.system(size: 11)).foregroundStyle(selected ? Theme.onAccent.opacity(0.8) : Theme.tertiaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .if(selected) { $0.liquidGlass(SkinShape(radius: 12), tint: palette.accent, interactive: true, rim: 0.3) }
    }
}

// MARK: - Workspace

struct WorkspaceView: View {
    @ObservedObject var session: DBSession
    @ObservedObject private var updater = Updater.shared
    @EnvironmentObject private var app: AppModel
    @EnvironmentObject private var chrome: WindowChrome
    @State private var showDetail = true
    @State private var showSidebar = true
    @State private var detail: RowDetailContext?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 8) {
            toolbar
            HStack(spacing: 8) {
                if showSidebar {
                    ItemSidebar(session: session)
                        .frame(width: 240)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                VStack(spacing: 6) {
                    TabStrip(session: session)
                    content
                        .clipShape(SkinShape(radius: 14))
                        .liquidGlass(SkinShape(radius: 14), rim: 0.2)
                }
                if showDetail {
                    RowDetailPanel(context: detail)
                        .frame(width: 290)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .animation(Theme.spring, value: showDetail)
        .animation(Theme.spring, value: showSidebar)
        .onChange(of: session.activeTabID) { _, _ in detail = nil }
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 4) {
                    ToolButton(symbol: "eject", help: "Close connection  ⌘[") { app.closeConnectionView() }
                    ToolButton(symbol: "sidebar.left", help: "Show or hide items", active: showSidebar) { showSidebar.toggle() }
                }
            }
            connectionBadge
            Spacer(minLength: 10)
            ThemeGauge(active: session.runningCount > 0)
            GlassGroup(spacing: 10) {
                HStack(spacing: 4) {
                    if let release = updater.available {
                        ToolButton(symbol: "arrow.down.circle.fill", title: "Update", help: "DChimera \(release.version) is available", active: true) {
                            updater.showDialog = true
                        }
                    }
                    ToolButton(symbol: "arrow.clockwise", help: "Refresh  ⌘R") { refresh() }
                    ToolButton(symbol: "plus.rectangle.on.rectangle", title: "SQL", help: "New SQL query tab  ⌘T") { session.newQueryTab() }
                    ToolButton(symbol: "clock.arrow.circlepath", help: "Query history") {
                        let q = session.newQueryTab()
                        q.text = session.history.reversed().prefix(30).map { $0.sql + ";" }.joined(separator: "\n\n")
                    }
                    ToolButton(symbol: "magnifyingglass", help: "Open anything  ⌘K") { withAnimation(Theme.bouncy) { app.quickSwitcher = true } }
                    ToolButton(symbol: "sidebar.right", help: "Row details", active: showDetail) { showDetail.toggle() }
                }
            }
        }
        .padding(.leading, max(chrome.leadingInset - 10, 0))
        .padding(.horizontal, 6)
        .frame(height: max(2 * chrome.controls.midY, 40))
    }

    private var connectionBadge: some View {
        let tag = session.config.envTag
        return HStack(spacing: 8) {
            Circle().fill(session.isConnected ? Theme.success : (session.isFailed ? Theme.danger : Theme.tertiaryText)).frame(width: 7, height: 7)
            Tag(text: tag.0, color: tag.1)
            Text(session.serverVersion.isEmpty ? session.config.kind.title : session.serverVersion)
                .foregroundStyle(Theme.secondaryText)
            Text(":").foregroundStyle(Theme.tertiaryText)
            Text(session.config.displayName).fontWeight(.semibold)
            if let table = session.activeTab?.table {
                Text(":").foregroundStyle(Theme.tertiaryText)
                Text(table.schema).foregroundStyle(Theme.secondaryText)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 30)
        .liquidGlass(SkinShape.capsule, clear: true, rim: 0.3)
        .frame(maxWidth: 520)
    }

    private func refresh() {
        Task {
            if let t = session.activeTab?.table { await session.model(for: t).reload() } else { await session.reloadSchema() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let tab = session.activeTab {
            switch tab.kind {
            case .table(let table):
                TableTabView(session: session, model: session.model(for: table)) { detail = $0 }
                    .id(tab.id)
            case .query(let qid):
                if let query = session.queryTab(qid) {
                    QueryTabView(session: session, query: query, editor: session.editor) { detail = $0 }
                        .id(tab.id)
                }
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "tablecells").font(.system(size: 34)).foregroundStyle(Theme.tertiaryText)
                Text("Open a table from the list, or press ⌘T for a new SQL query")
                    .foregroundStyle(Theme.secondaryText)
                HStack {
                    PillButton(title: "New SQL query", symbol: "plus", prominent: true) { session.newQueryTab() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.grid)
        }
    }
}

// MARK: - Item sidebar

struct ItemSidebar: View {
    @ObservedObject var session: DBSession
    @State private var query = ""
    @State private var collapsed: Set<String> = []
    @Environment(\.palette) private var palette

    private var tables: [TableRef] { session.tables.filter { $0.kind == .table && matches($0) } }
    private var views: [TableRef] { session.tables.filter { $0.kind != .table && matches($0) } }

    private func matches(_ t: TableRef) -> Bool {
        query.isEmpty || t.name.localizedCaseInsensitiveContains(query)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
                TextField("Search for item…", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.field))
            .padding(10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    section("Tables", items: tables, symbol: "tablecells")
                    section("Views", items: views, symbol: "eye")
                    let saved = session.starred
                    if !saved.isEmpty {
                        header("Saved queries", count: saved.count)
                        if !collapsed.contains("Saved queries") {
                            ForEach(saved.prefix(20)) { item in
                                ItemRow(symbol: "bookmark", title: SQLText.preview(item.sql), trailing: nil, selected: false) {
                                    session.newQueryTab(text: item.sql)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }
            HStack(spacing: 4) {
                Text(session.statusLine).font(.system(size: 10.5)).foregroundStyle(Theme.tertiaryText).lineLimit(1)
                Spacer()
                ToolButton(symbol: "arrow.clockwise", help: "Reload items") { Task { await session.reloadSchema() } }
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
        }
        .glassSurface(SkinShape(radius: 16))
    }

    @ViewBuilder
    private func section(_ title: String, items: [TableRef], symbol: String) -> some View {
        if !items.isEmpty {
            header(title, count: items.count)
            if !collapsed.contains(title) {
                ForEach(items) { t in
                    ItemRow(symbol: symbol, title: t.name, trailing: t.estimatedRows.map { Fmt.compact($0) },
                            selected: session.activeTab?.table == t) {
                        session.openTableTab(t)
                    }
                    .contextMenu {
                        Button("Open") { session.openTableTab(t) }
                        Button("Open in SQL Query") { session.newQueryTab(text: "SELECT * FROM \(session.config.kind.dialect.qualified(t)) LIMIT 100;") }
                        Button("Show DDL") {
                            session.openTableTab(t)
                            session.model(for: t).mode = 2
                        }
                        Button("Copy DDL") {
                            let m = session.model(for: t)
                            Task {
                                await m.loadDetails()
                                Exporter.copy(m.details?.ddl ?? "")
                                AppModel.shared.showToast(m.details?.ddl == nil ? "DDL not available" : "DDL copied", symbol: "doc.on.doc.fill")
                            }
                        }
                        Divider()
                        Button("Copy Name") { Exporter.copy(t.name) }
                    }
                }
            }
        }
    }

    private func header(_ title: String, count: Int) -> some View {
        Button {
            withAnimation(Theme.spring) {
                if collapsed.contains(title) { collapsed.remove(title) } else { collapsed.insert(title) }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(collapsed.contains(title) ? 0 : 90))
                Text(title.uppercased()).font(.system(size: 10.5, weight: .bold)).tracking(0.5)
                Text("\(count)").font(.system(size: 10.5)).foregroundStyle(Theme.tertiaryText)
                Spacer()
            }
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
            .padding(.top, 10)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ItemRow: View {
    let symbol: String
    let title: String
    let trailing: String?
    let selected: Bool
    let action: () -> Void
    @State private var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(selected ? Theme.onAccent : palette.accent).frame(width: 16)
            Text(title).font(.system(size: 12.5)).lineLimit(1)
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.system(size: 10.5)).foregroundStyle(selected ? Theme.onAccent.opacity(0.8) : Theme.tertiaryText) }
        }
        .foregroundStyle(selected ? Theme.onAccent : Theme.text)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .contentShape(Rectangle())
        .if(selected) { $0.liquidGlass(SkinShape(radius: 8), tint: palette.accent, interactive: true, rim: 0.3) }
        .if(!selected) { $0.background(RoundedRectangle(cornerRadius: 8).fill(hover ? Theme.hover : .clear)) }
        .onTapGesture(perform: action)
        .onHover { hover = $0 }
    }
}

// MARK: - Tabs

struct TabStrip: View {
    @ObservedObject var session: DBSession
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassGroup(spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(session.tabs) { tab in
                        TabChip(title: title(tab), symbol: symbol(tab), active: session.activeTabID == tab.id,
                                select: { withAnimation(Theme.spring) { session.activeTabID = tab.id } },
                                close: { withAnimation(Theme.spring) { session.closeTab(tab.id) } })
                    }
                    ToolButton(symbol: "plus", help: "New SQL query  ⌘T") {
                        withAnimation(Theme.spring) { _ = session.newQueryTab() }
                    }
                }
                .padding(.vertical, 3)
                .padding(.horizontal, 2)
            }
        }
        .frame(height: 38)
        .animation(Theme.spring, value: session.tabs.map(\.id))
    }

    private func title(_ tab: WorkTab) -> String {
        switch tab.kind {
        case .table(let t): t.name
        case .query(let id): session.queryTab(id)?.title ?? "SQL Query"
        }
    }

    private func symbol(_ tab: WorkTab) -> String {
        switch tab.kind {
        case .table(let t): t.kind == .table ? "tablecells" : "eye"
        case .query: "chevron.left.forwardslash.chevron.right"
        }
    }
}

struct TabChip: View {
    let title: String
    let symbol: String
    let active: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 10.5)).foregroundStyle(active ? Theme.onAccent : palette.accent)
            Text(title).font(.system(size: 12, weight: active ? .semibold : .regular)).lineLimit(1)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(hover ? Theme.hover : Color.clear))
            }
            .buttonStyle(.plain)
            .opacity(hover || active ? 1 : 0)
        }
        .foregroundStyle(active ? Theme.onAccent : Theme.text)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 30)
        .contentShape(Capsule())
        .liquidGlass(SkinShape.capsule, tint: active ? palette.accent : nil, clear: !active, interactive: true, rim: active || hover ? 0.45 : 0.15)
        .onTapGesture(perform: select)
        .onHover { hover = $0 }
    }
}

// MARK: - Row detail

struct RowDetailContext {
    var title: String
    var columns: [String]
    var types: [String]
    var values: [String?]
    var row: Int
    var onEdit: ((Int, String?) -> Void)?
}

struct RowDetailPanel: View {
    let context: RowDetailContext?
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Row").font(.system(size: 12.5, weight: .bold))
                if let context { Text("#\(context.row + 1) · \(context.title)").font(.system(size: 11.5)).foregroundStyle(Theme.secondaryText).lineLimit(1) }
                Spacer()
            }
            .padding(12)
            Divider().opacity(0.4)
            if let context {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(context.columns.indices, id: \.self) { i in
                            RowField(name: context.columns[i], type: i < context.types.count ? context.types[i] : "",
                                     value: i < context.values.count ? context.values[i] : nil,
                                     onEdit: context.onEdit.map { edit in { edit(i, $0) } })
                        }
                    }
                    .padding(12)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "cursorarrow.click.2").font(.system(size: 26)).foregroundStyle(Theme.tertiaryText)
                    Text("Select a cell to see its row").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .glassSurface(SkinShape(radius: 16))
    }
}

struct RowField: View {
    let name: String
    let type: String
    let value: String?
    let onEdit: ((String?) -> Void)?
    @State private var draft = ""
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                Text(type.lowercased()).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.tertiaryText)
                Spacer()
                if onEdit != nil && !editing {
                    Button("Edit") { draft = value ?? ""; editing = true }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(Theme.secondaryText)
                }
            }
            if editing {
                TextField("", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, design: .monospaced))
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
                    .onSubmit { onEdit?(draft); editing = false }
                HStack {
                    Button("Set NULL") { onEdit?(nil); editing = false }
                    Spacer()
                    Button("Cancel") { editing = false }
                    Button("Apply") { onEdit?(draft); editing = false }.keyboardShortcut(.defaultAction)
                }
                .font(.system(size: 11))
            } else {
                Text(value.map { $0.utf8.count > 4000 ? String($0.prefix(4000)) + "…" : $0 } ?? "NULL")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(value == nil ? Theme.tertiaryText : Theme.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(7)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
            }
        }
    }
}

// MARK: - Table tab

struct TableTabView: View {
    @ObservedObject var session: DBSession
    @ObservedObject var model: TableDataModel
    var onDetail: (RowDetailContext?) -> Void
    @State private var filterColumn = ""
    @State private var filterOp = "="
    @State private var filterValue = ""
    @State private var rawFilter = false
    @Environment(\.palette) private var palette

    private let operators = ["=", "<>", ">", ">=", "<", "<=", "LIKE", "NOT LIKE", "IN", "IS NULL", "IS NOT NULL"]

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider().opacity(0.4)
            ZStack {
                switch model.mode {
                case 1: StructureView(model: model)
                case 2: DDLView(model: model)
                default: data
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider().opacity(0.4)
            bottomBar
        }
        .task { await model.loadIfNeeded() }
    }

    private var columns: [String] { model.details?.columns.map(\.name) ?? (model.result?.columns ?? []) }

    private var filterBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Theme.tertiaryText)
            if rawFilter {
                Text("WHERE").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(SyntaxColors.keyword.asColor)
                TextField("condition", text: $model.filterText).textFieldStyle(.plain).font(Theme.mono(12))
                    .onSubmit { model.applyFilter() }
            } else {
                Menu(filterColumn.isEmpty ? "column" : filterColumn) {
                    ForEach(columns, id: \.self) { c in Button(c) { filterColumn = c } }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Menu(filterOp) {
                    ForEach(operators, id: \.self) { op in Button(op) { filterOp = op } }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if !filterOp.hasPrefix("IS") {
                    TextField(filterOp == "IN" ? "a, b, c" : "value", text: $filterValue)
                        .textFieldStyle(.plain)
                        .font(Theme.mono(12))
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.field))
                        .onSubmit { applyBuilt() }
                }
            }
            Spacer()
            Toggle("SQL", isOn: $rawFilter).toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            Button("Apply") { rawFilter ? model.applyFilter() : applyBuilt() }
                .glassButton(prominent: true)
                .controlSize(.small)
            if !model.appliedFilter.isEmpty {
                Button("Clear") {
                    filterValue = ""
                    model.filterText = ""
                    model.applyFilter()
                }
                .glassButton()
                .controlSize(.small)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(Theme.gridHeader)
    }

    private func applyBuilt() {
        guard !filterColumn.isEmpty else { return }
        let d = model.dialect
        let col = d.ident(filterColumn)
        let cond: String
        switch filterOp {
        case "IS NULL", "IS NOT NULL": cond = "\(col) \(filterOp)"
        case "IN":
            let items = filterValue.split(separator: ",").map { d.literal($0.trimmingCharacters(in: .whitespaces)) }
            cond = "\(col) IN (\(items.joined(separator: ", ")))"
        default: cond = "\(col) \(filterOp) \(d.literal(filterValue))"
        }
        model.applyFilter(cond)
    }

    @ViewBuilder
    private var data: some View {
        if let error = model.error, model.result == nil {
            Text(error).font(Theme.mono(12)).foregroundStyle(Theme.danger).padding(30)
        } else if let r = model.result {
            DataGrid(columns: r.columns, types: r.columnTypes, rows: r.rows, visible: model.visibleColumns,
                     rowOffset: model.page * model.pageSize, sort: model.sort,
                     onSort: model.pendingCount == 0 ? { model.toggleSort($0) } : nil,
                     editable: model.canEdit, edits: model.edits, deleted: model.deleted, extraRows: model.newRows,
                     onEdit: { key, value in model.setValue(value, at: key) },
                     onToggleDelete: { model.toggleDelete(row: $0) },
                     onFilter: { column, value, exclude in
                         let d = model.dialect
                         let cond = value.map { "\(d.ident(column)) \(exclude ? "<>" : "=") \(d.literal($0))" } ?? "\(d.ident(column)) IS \(exclude ? "NOT " : "")NULL"
                         model.applyFilter(cond)
                     },
                     onSelect: { key in onDetail(key.map(context)) })
                .id(model.loadedAt)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func context(_ key: CellKey) -> RowDetailContext {
        let r = model.result ?? QueryResult()
        let cols = model.visibleColumns
        let values = cols.map { c -> String? in model.value(CellKey(row: key.row, column: c)) }
        return RowDetailContext(title: model.table.name, columns: cols.map { r.columns[$0] },
                                types: cols.map { $0 < r.columnTypes.count ? r.columnTypes[$0] : "" },
                                values: values, row: model.page * model.pageSize + key.row,
                                onEdit: model.canEdit ? { i, v in
                                    model.setValue(v, at: CellKey(row: key.row, column: cols[i]))
                                } : nil)
    }

    private var bottomBar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $model.mode) {
                Text("Data").tag(0)
                Text("Structure").tag(1)
                Text("DDL").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 220)
            if model.canEdit {
                ToolButton(symbol: "plus", help: "Add row") { model.addRow() }
            }
            if model.pendingCount > 0 {
                Text("\(model.pendingCount) change\(model.pendingCount == 1 ? "" : "s")")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Theme.edited)
                Button("Discard") { model.discard() }.glassButton().controlSize(.small)
                Button(model.saving ? "Committing…" : "Commit") { Task { await model.save() } }
                    .glassButton(prominent: true)
                    .controlSize(.small)
                    .keyboardShortcut("s", modifiers: .command)
            }
            Spacer()
            if let hint = model.editHint {
                Text(hint).font(.system(size: 11)).foregroundStyle(Theme.tertiaryText)
            }
            ToolButton(symbol: "chevron.left", help: "Previous page") { model.go(toPage: model.page - 1) }
                .disabled(model.page == 0)
            Text(rangeText).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(Theme.secondaryText)
            ToolButton(symbol: "chevron.right", help: "Next page") { model.go(toPage: model.page + 1) }
                .disabled(!model.hasNextPage)
            Menu("\(model.pageSize)") {
                ForEach([50, 100, 200, 500, 1000], id: \.self) { n in Button("\(n) rows") { model.setPageSize(n) } }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            if model.exactCount == nil {
                Button("Count") { Task { await model.countRows() } }.buttonStyle(.plain).font(.system(size: 11.5)).foregroundStyle(palette.accent)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 38)
        .background(Theme.gridHeader)
    }

    private var rangeText: String {
        let n = model.result?.rows.count ?? 0
        let from = n == 0 ? 0 : model.page * model.pageSize + 1
        return "\(Fmt.grouped(from))–\(Fmt.grouped(model.page * model.pageSize + n)) of \(model.totalLabel)"
    }
}

/// CREATE statement of the table (or view), highlighted, with a copy button.
struct DDLView: View {
    @ObservedObject var model: TableDataModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.table.kind == .table ? "CREATE TABLE" : "CREATE VIEW")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                ToolButton(symbol: "doc.on.doc", title: "Copy DDL", help: "Copy the CREATE statement", glass: false) {
                    Exporter.copy(model.details?.ddl ?? "")
                    AppModel.shared.showToast("DDL copied", symbol: "doc.on.doc.fill")
                }
                .disabled(model.details?.ddl == nil)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            Divider().opacity(0.4)
            if let details = model.details {
                GeometryReader { geo in
                    ScrollView([.vertical, .horizontal]) {
                        Text(SyntaxColors.attributed(details.ddl ?? "-- the database did not return a definition", onAccent: false, size: 12.5))
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(14)
                            .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await model.loadDetails() }
    }
}

/// A read-only grid of a few rows already in memory, sorted by header clicks (Structure view).
struct SortableGrid: View {
    let columns: [String]
    let rows: [[String?]]
    @State private var sort: SortSpec?

    var body: some View {
        DataGrid(columns: columns, types: [], rows: LocalSort.sorted(rows, columns: columns, by: sort),
                 sort: sort, onSort: { column in sort = LocalSort.next(sort, column) })
    }
}

struct StructureView: View {
    @ObservedObject var model: TableDataModel

    var body: some View {
        if let d = model.details {
            VStack(spacing: 0) {
                SortableGrid(columns: ["column", "type", "nullable", "default", "key", "references"],
                             rows: d.columns.map { [$0.name, $0.type, $0.nullable ? "YES" : "NO", $0.defaultValue, $0.isPrimaryKey ? "PRI" : nil, $0.references] })
                Divider().opacity(0.4)
                SortableGrid(columns: ["index", "columns", "unique", "definition"],
                             rows: d.indexes.map { [$0.name, $0.columns.joined(separator: ", "), $0.unique ? "YES" : "NO", $0.definition] })
                    .frame(height: 170)
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - SQL query tab

struct QueryTabView: View {
    @ObservedObject var session: DBSession
    @ObservedObject var query: QueryTab
    @ObservedObject var editor: EditorController
    var onDetail: (RowDetailContext?) -> Void
    @State private var height: CGFloat = 60
    @State private var editorHeight: CGFloat = 220
    @State private var dragStart: CGFloat?
    @AppStorage("editorFontSize") private var fontSize: Double = 13
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                PillButton(title: "Run Current", symbol: "play.fill", prominent: true) { session.runQueryTab(query, all: false) }
                    .help("⌘↩")
                ToolButton(symbol: "forward.fill", title: "Run All", help: "⇧⌘↩") { session.runQueryTab(query, all: true) }
                ToolButton(symbol: "bookmark", title: "Save", help: "Save to the item list") {
                    session.setStar(sql: query.text, starred: true)
                    AppModel.shared.showToast("Saved", symbol: "bookmark.fill")
                }
                Spacer()
                if query.running { ProgressView().controlSize(.small) }
                Text(query.title).font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(Theme.gridHeader)
            SQLEditor(text: $query.text, contentHeight: $height, controller: editor, fontSize: CGFloat(fontSize),
                      onRun: { all in session.runQueryTab(query, all: all) },
                      onHistoryUp: { if let last = session.history.last { editor.setText(last.sql) } })
                .padding(10)
                .frame(height: editorHeight)
                .background(Theme.field)
                .overlay(alignment: .topLeading) {
                    CompletionPopup(controller: editor)
                        .offset(x: 10 + min(max(editor.anchor.x, 0), 420), y: 10 + editor.anchor.y + 20)
                }
                .zIndex(2)
            Rectangle()
                .fill(Theme.gridLine)
                .frame(height: 5)
                .overlay(Capsule().fill(Theme.tertiaryText).frame(width: 36, height: 3))
                .gesture(DragGesture().onChanged { g in
                    if dragStart == nil { dragStart = editorHeight }
                    editorHeight = min(max(90, (dragStart ?? 220) + g.translation.height), 600)
                }.onEnded { _ in dragStart = nil })
                .onHover { inside in if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() } }
            results
            HStack {
                Text(query.messages.last ?? "Ready").font(.system(size: 11)).foregroundStyle(query.error == nil ? Theme.secondaryText : Theme.danger).lineLimit(1)
                Spacer()
                if let r = query.result {
                    Menu("Export") {
                        ForEach(ExportFormat.allCases) { f in
                            Button("Copy as \(f.title)") { Exporter.copy(Exporter.render(query.shownResult ?? r, as: f)) }
                        }
                        Divider()
                        ForEach(ExportFormat.allCases) { f in
                            Button("Save as \(f.title)…") { _ = Exporter.save(query.shownResult ?? r, as: f, suggestedName: query.title) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Theme.gridHeader)
        }
        .background(Theme.grid)
        .onAppear {
            editor.tables = { [weak session] in session?.tables ?? [] }
            editor.columns = { [weak session] in session?.columns ?? [] }
            DispatchQueue.main.async { editor.focus() }
        }
    }

    @ViewBuilder
    private var results: some View {
        if let error = query.error {
            ScrollView {
                Text(error).font(Theme.mono(12)).foregroundStyle(Theme.danger).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }
        } else if let r = query.result {
            let rows = query.shownRows
            DataGrid(columns: r.columns, types: r.columnTypes, rows: rows,
                     sort: query.sort, onSort: { column in
                         query.toggleSort(column)
                         onDetail(nil) // the grid drops its selection when the order changes
                     },
                     onSelect: { key in
                         onDetail(key.map { k in
                             RowDetailContext(title: query.title, columns: r.columns, types: r.columnTypes,
                                              values: k.row < rows.count ? rows[k.row] : [], row: k.row, onEdit: nil)
                         })
                     })
        } else {
            VStack(spacing: 6) {
                Text("⌘↩ runs the statement under the cursor, ⇧⌘↩ runs everything")
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
