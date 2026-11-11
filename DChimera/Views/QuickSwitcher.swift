import SwiftUI

/// ⌘K: jump to any connection, table, saved query or action.
struct QuickSwitcher: View {
    @EnvironmentObject private var app: AppModel
    @State private var query = ""
    @State private var selected = 0
    @State private var monitor: Any?
    @State private var appeared = false
    @FocusState private var focused: Bool
    @Environment(\.palette) private var palette

    struct Item: Identifiable {
        enum Kind { case connection, table, query, action }
        let id: String
        var kind: Kind
        var title: String
        var subtitle: String
        var symbol: String
        var colorIndex: Int
        var initials: String?
        var run: () -> Void
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(appeared ? 0.28 : 0)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    TextField("Jump to a connection, table or query…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 17))
                        .focused($focused)
                    Text("esc")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.tertiaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 5).stroke(Theme.tertiaryText.opacity(0.5)))
                }
                .padding(.horizontal, 16)
                .frame(height: 56)
                HairlineDivider()
                let items = results
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                                if i == 0 || items[i - 1].kind != item.kind {
                                    Text(sectionTitle(item.kind))
                                        .font(.system(size: 10.5, weight: .bold))
                                        .tracking(0.6)
                                        .foregroundStyle(Theme.tertiaryText)
                                        .padding(.horizontal, 12)
                                        .padding(.top, i == 0 ? 6 : 12)
                                        .padding(.bottom, 4)
                                }
                                row(item, selected: i == selected)
                                    .id(item.id)
                                    .onTapGesture { choose(item) }
                                    .onHover { if $0 { selected = i } }
                            }
                            if items.isEmpty {
                                Text("Nothing matches “\(query)”")
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(30)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 420)
                    .onChange(of: selected) { _, new in
                        guard new < items.count else { return }
                        withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(items[new].id, anchor: .center) }
                    }
                }
            }
            .frame(width: 600)
            .clipShape(RoundedRectangle(cornerRadius: Skin.current.cardRadius, style: .continuous))
            .skinPopup()
            .scaleEffect(appeared ? 1 : 0.92, anchor: .top)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : -14)
            .padding(.top, 90)
        }
        .onAppear {
            withAnimation(Theme.bouncy) { appeared = true }
            focused = true
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 125: selected = min(selected + 1, max(results.count - 1, 0)); return nil
                case 126: selected = max(selected - 1, 0); return nil
                case 36, 76:
                    let items = results
                    if selected < items.count { choose(items[selected]) }
                    return nil
                case 53: close(); return nil
                default: return event
                }
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 10) {
            if let initials = item.initials {
                AvatarView(initials: initials, colorIndex: item.colorIndex, size: 30)
            } else {
                TopicIcon(symbol: item.symbol, colorIndex: item.colorIndex, size: 30)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(selected ? Theme.onAccent.opacity(0.85) : Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            if selected {
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .bold))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(selected ? Theme.onAccent : .primary)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear))
        )
        .contentShape(Rectangle())
        .animation(.spring(response: 0.2, dampingFraction: 0.85), value: selected)
    }

    private func sectionTitle(_ kind: Item.Kind) -> String {
        switch kind {
        case .connection: "CONNECTIONS"
        case .table: "TABLES"
        case .query: "QUERIES"
        case .action: "ACTIONS"
        }
    }

    private var allItems: [Item] {
        var items: [Item] = []
        for c in app.sortedConnections {
            let id = c.id
            items.append(Item(id: "c-\(c.id)", kind: .connection, title: c.displayName, subtitle: "\(c.kind.title) · \(c.subtitle)",
                              symbol: c.kind.symbol, colorIndex: c.colorIndex, initials: c.initials) { app.open(id) })
        }
        let sessions = app.sortedConnections.compactMap { app.session($0.id) }
        for s in sessions where s.isConnected {
            for t in s.tables {
                let sid = s.id
                items.append(Item(id: "t-\(s.id)-\(t.id)", kind: .table, title: t.name,
                                  subtitle: "\(s.config.displayName) · \(t.schema)" + (t.estimatedRows.map { " · \(Fmt.compact($0)) rows" } ?? ""),
                                  symbol: t.symbol, colorIndex: Theme.colorIndex(for: t.name), initials: nil) { app.openTable(t, in: sid) })
            }
        }
        for s in sessions {
            var seen = Set<String>()
            for h in s.history.reversed().prefix(40) where seen.insert(h.sql).inserted {
                let sid = s.id, sql = h.sql
                items.append(Item(id: "q-\(h.id)", kind: .query, title: SQLText.preview(h.sql), subtitle: s.config.displayName + (h.starred ? " · saved" : ""),
                                  symbol: h.starred ? "bookmark.fill" : "clock.fill", colorIndex: h.starred ? 1 : 2, initials: nil) {
                    app.open(sid)
                    app.session(sid)?.newQueryTab(text: sql)
                })
            }
        }
        items.append(Item(id: "a-new", kind: .action, title: "New connection", subtitle: "⌘N", symbol: "plus", colorIndex: 3, initials: nil) { app.newConnection() })
        items.append(Item(id: "a-demo", kind: .action, title: "Add demo database", subtitle: "A small SQLite shop to play with", symbol: "sparkles", colorIndex: 6, initials: nil) { app.addDemoDatabase() })
        if let s = app.openSession {
            items.append(Item(id: "a-sql", kind: .action, title: "New SQL query", subtitle: s.config.displayName, symbol: "chevron.left.forwardslash.chevron.right", colorIndex: 5, initials: nil) {
                s.newQueryTab()
            })
        }
        items.append(Item(id: "a-theme", kind: .action, title: "Toggle dark mode", subtitle: "Switch between light and dark", symbol: "moon.stars.fill", colorIndex: 2, initials: nil) {
            let current = Appearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "system") ?? .system
            let isDark = current == .dark || (current == .system && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
            UserDefaults.standard.set(isDark ? Appearance.light.rawValue : Appearance.dark.rawValue, forKey: "appearance")
        })
        for kind in SkinKind.allCases {
            items.append(Item(id: "a-skin-\(kind.rawValue)", kind: .action, title: "Theme: \(kind.title)", subtitle: kind.subtitle,
                              symbol: kind.symbol, colorIndex: kind.colorIndex, initials: nil) {
                UserDefaults.standard.set(kind.rawValue, forKey: "skin")
            })
        }
        if let s = app.openSession {
            items.append(Item(id: "a-reload", kind: .action, title: "Reload schema", subtitle: s.config.displayName, symbol: "arrow.clockwise", colorIndex: 4, initials: nil) {
                Task { await s.reloadSchema() }
            })
        }
        return items
    }

    private var results: [Item] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let items = allItems
        if q.isEmpty {
            let connections = items.filter { $0.kind == .connection }.prefix(6)
            let queries = items.filter { $0.kind == .query }.prefix(4)
            let actions = items.filter { $0.kind == .action }
            return Array(connections) + Array(queries) + actions
        }
        let scored = items.compactMap { item -> (Item, Int)? in
            guard let s = Self.score(q, in: item.title.lowercased()) ?? Self.score(q, in: item.subtitle.lowercased()).map({ $0 - 30 }) else { return nil }
            return (item, s)
        }
        let order: [Item.Kind] = [.connection, .table, .query, .action]
        let grouped = order.flatMap { kind in
            scored.filter { $0.0.kind == kind }.sorted { $0.1 > $1.1 }.prefix(kind == .table ? 12 : 6).map(\.0)
        }
        return grouped
    }

    /// Fuzzy subsequence score; nil when the letters do not appear in order.
    static func score(_ query: String, in text: String) -> Int? {
        if text.hasPrefix(query) { return 1000 - text.count }
        if text.contains(query) { return 700 - text.count }
        var score = 0
        var ti = text.startIndex
        var last: String.Index?
        for ch in query {
            guard let found = text[ti...].firstIndex(of: ch) else { return nil }
            if let last, text.index(after: last) == found { score += 8 }
            score += 2
            last = found
            ti = text.index(after: found)
        }
        return score
    }

    private func choose(_ item: Item) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { item.run() }
    }

    private func close() {
        withAnimation(Theme.spring) { appeared = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            app.quickSwitcher = false
        }
    }
}
