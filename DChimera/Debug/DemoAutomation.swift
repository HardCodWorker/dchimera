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

    /// Picture of the visible part of the data grid (an NSTableView).
    static func gridShot(_ name: String, _ dir: URL) {
        func find(_ v: NSView) -> GridTableView? {
            if let t = v as? GridTableView { return t }
            for sub in v.subviews { if let t = find(sub) { return t } }
            return nil
        }
        guard let table = mainWindow?.contentView.flatMap(find), let rep = table.bitmapImageRepForCachingDisplay(in: table.visibleRect) else { return }
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
#endif
