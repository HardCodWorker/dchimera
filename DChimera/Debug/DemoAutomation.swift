#if DEBUG
import AppKit
import SwiftUI

/// Debug-only self test. Runs only when DCHIMERA_DEMO_OUT is set: goes through the workspace in every
/// theme against the demo SQLite database, saves window snapshots (PNG) and writes tour.txt.
@MainActor
enum DemoAutomation {
    static func startIfRequested() {
        guard let out = ProcessInfo.processInfo.environment["DCHIMERA_DEMO_OUT"], !out.isEmpty else { return }
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        Task { await run(dir) }
    }

    private static func wait(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !($0 is NSPanel) && $0.contentView != nil && $0.frame.width > 600 }
    }

    /// Renders the app's own window views into a PNG (no screen capture, no permission needed).
    /// System Liquid Glass and AppKit views hosted in SwiftUI do not show up in these pictures.
    static func shot(_ name: String, _ dir: URL) {
        guard let window = mainWindow, let content = window.contentView else { return }
        let view = content.superview ?? content
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    static var lastHit = ""

    static var grids: [GridTableView] {
        func find(_ v: NSView) -> [GridTableView] {
            if let t = v as? GridTableView { return [t] }
            return v.subviews.flatMap(find)
        }
        return mainWindow?.contentView.map(find) ?? []
    }

    static var grid: GridTableView? { grids.first }

    /// The grid that has `column`, with the column's values in the order it shows them.
    static func shown(_ column: String) -> (table: GridTableView, columns: [String], values: [String?])? {
        for table in grids {
            guard let g = table.controller?.config, let c = g.columns.firstIndex(of: column) else { continue }
            return (table, g.columns, g.rows.map { c < $0.count ? $0[c] : nil })
        }
        return nil
    }

    /// A real click on a grid header: mouse down and up go through the window, the header view tracks them.
    static func clickHeader(_ column: String, columns _: [String] = []) -> Bool {
        guard let window = mainWindow, let found = shown(column), let header = found.table.headerView,
              let c = found.columns.firstIndex(of: column), case let table = found.table,
              let index = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "c\(c)" }) else { return false }
        table.scrollColumnToVisible(index)
        let rect = header.headerRect(ofColumn: index)
        let point = header.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
        func event(_ type: NSEvent.EventType) -> NSEvent? {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                               pressure: type == .leftMouseDown ? 1 : 0)
        }
        guard let down = event(.leftMouseDown), let up = event(.leftMouseUp) else { return false }
        if let root = window.contentView?.superview ?? window.contentView {
            let hit = root.hitTest(root.convert(point, from: nil))
            lastHit = (hit.map { String(describing: type(of: $0)) } ?? "nil") + " key=\(window.isKeyWindow) active=\(NSApp.isActive)"
        }
        NSApp.postEvent(up, atStart: false)
        // The test app is not the active app (macOS will not activate it from a script), so a click through the
        // window would only activate it. Give the press to the header view itself; it tracks the posted release.
        header.mouseDown(with: down)
        return true
    }

    /// Clicks the header of `column` three times: ascending, descending, off. Returns one log line.
    static func sortCheck(_ name: String, model: TableDataModel, column: String) async -> String {
        func values() -> [String] {
            guard let r = model.result, let i = r.columns.firstIndex(of: column) else { return [] }
            return r.rows.compactMap { $0[i] }
        }
        func ordered(_ v: [String], ascending: Bool) -> Bool {
            v.count > 1 && zip(v, v.dropFirst()).allSatisfy { ascending ? $0 <= $1 : $0 >= $1 }
        }
        var steps: [String] = []
        for (n, expect) in [(1, "asc"), (2, "desc"), (3, "off")] {
            guard clickHeader(column, columns: model.result?.columns ?? []) else { return "\(name) sort: FAIL header \(column) not found" }
            await wait(0.9)
            let ok: Bool
            switch expect {
            case "asc": ok = model.sort?.column == column && model.sort?.ascending == true && ordered(values(), ascending: true)
            case "desc": ok = model.sort?.column == column && model.sort?.ascending == false && ordered(values(), ascending: false)
            default: ok = model.sort == nil
            }
            steps.append("click \(n) \(expect) \(ok ? "ok" : "FAIL (hit=\(lastHit), sort=\(String(describing: model.sort)), first=\(values().prefix(3)))")")
        }
        return "\(name) sort by \(column): " + steps.joined(separator: ", ")
    }

    /// Header sorting of rows already loaded (query results, Structure): ascending, descending, original order.
    static func localSortCheck(_ name: String, column: String, numeric: Bool) async -> String {
        func ordered(_ values: [String?]?, ascending: Bool) -> Bool {
            let v = (values ?? []).compactMap { $0 }
            guard v.count > 1 else { return false }
            return zip(v, v.dropFirst()).allSatisfy { a, b in
                let o: ComparisonResult
                if numeric, let x = Double(a), let y = Double(b) {
                    o = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
                } else {
                    o = a.localizedStandardCompare(b)
                }
                return ascending ? o != .orderedDescending : o != .orderedAscending
            }
        }
        guard let before = shown(column)?.values else {
            let seen = grids.map { "\($0.controller == nil ? "no controller" : ($0.controller?.config?.columns.joined(separator: ",") ?? "no config"))" }
            return "\(name) sort by \(column): FAIL no grid with that column (window: \(mainWindow != nil), grids: \(seen))"
        }
        var steps: [String] = []
        for (n, expect) in [(1, "asc"), (2, "desc"), (3, "original")] {
            guard clickHeader(column) else { return "\(name) sort by \(column): FAIL header not found" }
            await wait(0.7)
            let now = shown(column)?.values
            let ok: Bool
            switch expect {
            case "asc": ok = ordered(now, ascending: true) && now != before
            case "desc": ok = ordered(now, ascending: false)
            default: ok = now == before
            }
            steps.append("click \(n) \(expect) \(ok ? "ok" : "FAIL (first=\((now ?? []).prefix(3)))")")
        }
        return "\(name) sort by \(column): " + steps.joined(separator: ", ")
    }

    /// Picture of the visible part of the data grid (an NSTableView).
    static func gridShot(_ name: String, _ dir: URL) {
        guard let table = grid, let rep = table.bitmapImageRepForCachingDisplay(in: table.visibleRect) else { return }
        table.cacheDisplay(in: table.visibleRect, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
    }

    static func run(_ dir: URL) async {
        let app = AppModel.shared
        await wait(1.0)
        mainWindow?.setFrame(NSRect(x: 80, y: 80, width: 1320, height: 840), display: true)
        if app.connections.isEmpty {
            try? await DemoDatabase.create(at: AppPaths.demoDatabase)
            var demo = ConnectionConfig()
            demo.kind = .sqlite
            demo.name = "Demo Shop"
            demo.filePath = AppPaths.demoDatabase.path
            demo.colorIndex = 4
            demo.port = 0
            app.upsert(demo, password: nil)
            var pg = ConnectionConfig()
            pg.name = "Analytics prod"
            pg.host = "db.example.invalid"
            pg.user = "reader"
            pg.database = "analytics"
            pg.readOnly = true
            pg.colorIndex = 2
            pg.createdAt = Date().addingTimeInterval(-7200)
            app.upsert(pg, password: nil)
        }
        guard let demo = app.connections.first(where: { $0.kind == .sqlite }), let session = app.session(demo.id) else { return }

        let savedSkin = UserDefaults.standard.string(forKey: "skin")
        let savedAppearance = UserDefaults.standard.string(forKey: "appearance")
        var log = ["window buttons: \(app.chrome.controls)"]
        let names: [SkinKind: String] = [.telegram: "chat", .matrix: "matrix", .glass: "asphalt", .stalker: "stalker", .doom: "doom", .breakingBad: "breakingbad"]
        let only = ProcessInfo.processInfo.environment["DCHIMERA_DEMO_ONLY"]
        for (kind, appearance) in [(SkinKind.telegram, Appearance.light), (.matrix, .dark), (.glass, .dark), (.stalker, .dark), (.doom, .dark), (.breakingBad, .dark)] {
            let name = names[kind] ?? kind.rawValue
            if let only, !only.split(separator: ",").contains(Substring(name)) { continue }
            app.closeConnectionView()
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
            UserDefaults.standard.set(kind.rawValue, forKey: "skin")
            if Skin.make(kind).isScenic {
                await wait(0.4)
                shot("\(name)-0-effect", dir)
                await wait(1.6)
            } else {
                await wait(2.0)
            }
            shot("\(name)-1-welcome", dir)
            app.open(demo.id)
            await wait(1.2)
            if let customers = session.tables.first(where: { $0.name == "customers" }) {
                let model = session.model(for: customers)
                session.openTableTab(customers)
                model.mode = 0
                await wait(1.3)
                shot("\(name)-2-table", dir)
                gridShot("\(name)-2b-grid", dir)
                log.append(await sortCheck(name, model: model, column: "name"))
                model.mode = 1
                await wait(0.9)
                log.append(await localSortCheck("\(name) structure", column: "column", numeric: false))
                model.mode = 2
                await wait(0.9)
                shot("\(name)-3-ddl", dir)
                log.append("\(name) ddl starts with: \(model.details?.ddl?.prefix(40) ?? "nil")")
                model.mode = 0
            }
            let q = session.newQueryTab(text: "SELECT p.category, count(*) AS products, round(avg(p.price), 2) AS avg_price\nFROM products p\nGROUP BY p.category\nORDER BY avg_price DESC;")
            await wait(0.6)
            session.runQueryTab(q, all: true)
            await wait(1.2)
            shot("\(name)-4-query", dir)
            log.append("\(name) query rows = \(q.result?.rows.count ?? -1)")
            log.append(await localSortCheck("\(name) query", column: "avg_price", numeric: true))
            log.append(await localSortCheck("\(name) query", column: "category", numeric: false))
            for tab in session.tabs { session.closeTab(tab.id) }
        }
        try? log.joined(separator: "\n").write(to: dir.appendingPathComponent("tour.txt"), atomically: true, encoding: .utf8)
        // Put back the user's own theme choice.
        UserDefaults.standard.set(savedSkin, forKey: "skin")
        UserDefaults.standard.set(savedAppearance, forKey: "appearance")
        try? "ok".write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
        NSApp.terminate(nil)
    }
}
#endif

#if DEBUG
/// Debug-only update test. With DCHIMERA_UPDATE_SELFTEST=<log file> the app checks the feed in DCHIMERA_UPDATE_URL,
/// logs each state and, if a newer version is offered, installs it (the app quits and the new one opens).
@MainActor
enum UpdateSelfTest {
    static func startIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["DCHIMERA_UPDATE_SELFTEST"], !path.isEmpty else { return false }
        let log = URL(fileURLWithPath: path)
        Task {
            let updater = Updater.shared
            var lines = ["running \(updater.currentVersion) from \(Bundle.main.bundlePath)", "feed \(Updater.feedURL)"]
            func write() { try? lines.joined(separator: "\n").write(to: log, atomically: true, encoding: .utf8) }
            let shots = ProcessInfo.processInfo.environment["DCHIMERA_UPDATE_SHOTS"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            await updater.check(userInitiated: true)
            lines.append("after check: \(updater.state)")
            write()
            if let shots {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                DemoAutomation.shot("update-1-check", shots)
            }
            guard updater.available != nil else { return }
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            lines.append("installing")
            write()
            await updater.install()
            lines.append("install returned: \(updater.state)")
            write()
            if let shots {
                try? await Task.sleep(nanoseconds: 800_000_000)
                DemoAutomation.shot("update-2-after-install", shots)
            }
        }
        return true
    }
}

/// DCHIMERA_SETTINGS_SHOT=/path.png renders Settings → Claude (MCP) into a PNG and quits.
@MainActor
enum MCPSettingsShot {
    static func startIfRequested() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["DCHIMERA_SETTINGS_SHOT"], !path.isEmpty else { return false }
        let size = NSSize(width: 620, height: 560)
        let host = NSHostingView(rootView: Form { MCPSettingsSection() }.formStyle(.grouped).environmentObject(AppModel.shared))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: 120, y: 120))
        window.orderFront(nil)
        for w in NSApp.windows where w !== window { w.orderOut(nil) }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
        return true
    }
}
#endif
