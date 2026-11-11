import AppKit
import SwiftUI

/// psql-style text output.
enum TerminalFormat {
    static func cell(_ value: String?, maxWidth: Int) -> String {
        guard let value else { return "NULL" }
        var s = value.utf8.count > 400 ? String(value.prefix(400)) : value
        if s.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) {
            s = s.replacingOccurrences(of: "\r\n", with: "↵").replacingOccurrences(of: "\n", with: "↵")
                .replacingOccurrences(of: "\r", with: "↵").replacingOccurrences(of: "\t", with: " ")
        }
        if s.count > maxWidth { s = String(s.prefix(maxWidth - 1)) + "…" }
        return s
    }

    /// Aligned table like psql prints it: header, a dashed line, rows; numbers aligned to the right.
    static func table(_ r: QueryResult, maxRows: Int, maxWidth: Int = 42) -> String {
        guard !r.columns.isEmpty else { return "" }
        let numeric = r.numericColumns()
        let rows = r.rows.prefix(maxRows).map { row in r.columns.indices.map { c in cell(c < row.count ? row[c] : nil, maxWidth: maxWidth) } }
        var widths = r.columns.map { min($0.count, maxWidth) }
        for row in rows {
            for (c, v) in row.enumerated() where v.count > widths[c] { widths[c] = v.count }
        }
        func pad(_ s: String, _ w: Int, right: Bool) -> String {
            let gap = max(0, w - s.count)
            return right ? String(repeating: " ", count: gap) + s : s + String(repeating: " ", count: gap)
        }
        var lines: [String] = []
        lines.append(" " + r.columns.indices.map { c -> String in
            let name = cell(r.columns[c], maxWidth: maxWidth)
            let gap = max(0, widths[c] - name.count)
            return String(repeating: " ", count: gap / 2) + name + String(repeating: " ", count: gap - gap / 2)
        }.joined(separator: " | "))
        lines.append(widths.map { String(repeating: "-", count: $0 + 2) }.joined(separator: "+"))
        for row in rows {
            lines.append(" " + row.enumerated().map { c, v in pad(v, widths[c], right: numeric.contains(c)) }.joined(separator: " | "))
        }
        return lines.joined(separator: "\n")
    }

    static func prompt(_ config: ConnectionConfig) -> String {
        let slug = config.displayName.lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "_" }
            .joined()
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return slug.isEmpty ? "db" : String(slug.prefix(24))
    }

    static let logo: String = {
        let letters: [[String]] = [
            [" ____  ", "|  _ \\ ", "| | | |", "| |_| |", "|____/ "],
            ["  ____ ", " / ___|", "| |    ", "| |___ ", " \\____|"],
            [" _     ", "| |__  ", "| '_ \\ ", "| | | |", "|_| |_|"],
            [" _ ", "(_)", "| |", "| |", "|_|"],
            ["           ", " _ __ ___  ", "| '_ ` _ \\ ", "| | | | | |", "|_| |_| |_|"],
            ["      ", "  ___ ", " / _ \\", "|  __/", " \\___|"],
            ["      ", " _ __ ", "| '__|", "| |   ", "|_|   "],
            ["       ", "  __ _ ", " / _` |", "| (_| |", " \\__,_|"],
        ]
        return (0..<5).map { line in letters.map { $0[line] }.joined() }.joined(separator: "\n")
    }()
}
