#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: renders DataGrid off screen with a wide, heavy result and writes timings.
/// Runs only when DCHIMERA_BENCH_OUT is set; the app quits afterwards.
@MainActor
enum GridBenchmark {
    static func startIfRequested() -> Bool {
        guard let out = ProcessInfo.processInfo.environment["DCHIMERA_BENCH_OUT"], !out.isEmpty else { return false }
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            run(URL(fileURLWithPath: out))
            NSApp.terminate(nil)
        }
        return true
    }

    /// 1000 rows × 40 columns; every 7th column holds a ~5 KB JSON document, some cells are NULL.
    static func wideResult(rows: Int = 1000, cols: Int = 40) -> QueryResult {
        var r = QueryResult()
        r.columns = (0..<cols).map { $0 == 0 ? "id" : ($0 % 7 == 3 ? "payload_\($0)" : "col_\($0)") }
        r.columnTypes = (0..<cols).map { $0 == 0 ? "int8" : ($0 % 7 == 3 ? "jsonb" : "text") }
        let json = "{" + (0..<120).map { "\"key\($0)\": \"value number \($0) with some text\"" }.joined(separator: ", ") + "}"
        r.rows = (0..<rows).map { i in
            (0..<cols).map { c -> String? in
                if c == 0 { return "\(i)" }
                if c % 7 == 3 { return json }
                if c % 5 == 0 { return nil }
                return "segment \(i)-\(c) lorem ipsum"
            }
        }
        return r
    }

    static func run(_ out: URL) {
        let r = wideResult()
        var log: [String] = ["rows=\(r.rows.count) cols=\(r.columns.count) json=\(r.rows[0][3]?.utf8.count ?? 0) bytes"]
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1400, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: AnyView(DataGrid(columns: r.columns, types: r.columnTypes, rows: r.rows)))
        host.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        window.contentView = host

        func layout() -> Double {
            let t = CFAbsoluteTimeGetCurrent()
            host.layoutSubtreeIfNeeded()
            return (CFAbsoluteTimeGetCurrent() - t) * 1000
        }
        func draw() -> Double {
            let t = CFAbsoluteTimeGetCurrent()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
            }
            return (CFAbsoluteTimeGetCurrent() - t) * 1000
        }

        log.append(String(format: "first: layout %.1f ms, draw %.1f ms", layout(), draw()))
        var totalLayout = 0.0, totalDraw = 0.0
        for i in 0..<10 {
            let edits: [CellKey: String?] = [CellKey(row: i, column: 1): "x\(i)"]
            host.rootView = AnyView(DataGrid(columns: r.columns, types: r.columnTypes, rows: r.rows, edits: edits))
            let l = layout(), d = draw()
            totalLayout += l
            totalDraw += d
            log.append(String(format: "update %d: layout %.1f ms, draw %.1f ms", i, l, d))
        }
        log.append(String(format: "average update: layout %.1f ms, draw %.1f ms", totalLayout / 10, totalDraw / 10))
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? log.joined(separator: "\n").write(to: out, atomically: true, encoding: .utf8)
    }
}
#endif
