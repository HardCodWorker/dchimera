import AppKit
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable {
    case csv, json, markdown

    var id: String { rawValue }
    var title: String {
        switch self {
        case .csv: "CSV"
        case .json: "JSON"
        case .markdown: "Markdown"
        }
    }
    var fileExtension: String {
        switch self {
        case .csv: "csv"
        case .json: "json"
        case .markdown: "md"
        }
    }
}

enum Exporter {
    static func render(_ result: QueryResult, as format: ExportFormat) -> String {
        switch format {
        case .csv: csv(result)
        case .json: json(result)
        case .markdown: markdown(result)
        }
    }

    static func csv(_ result: QueryResult) -> String {
        func field(_ v: String?) -> String {
            guard let v else { return "" }
            if v.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) {
                return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return v
        }
        var lines = [result.columns.map(field).joined(separator: ",")]
        lines += result.rows.map { $0.map(field).joined(separator: ",") }
        return lines.joined(separator: "\n") + "\n"
    }

    static func json(_ result: QueryResult) -> String {
        let numeric = result.numericColumns()
        func value(_ v: String?, _ c: Int) -> String {
            guard let v else { return "null" }
            if numeric.contains(c), let d = Double(v), d.isFinite, !v.hasPrefix("0") || v == "0" || v.hasPrefix("0.") { return v }
            if v == "true" || v == "false" { return v }
            return jsonString(v)
        }
        let objects = result.rows.map { row -> String in
            let pairs = result.columns.indices.map { c in "    \(jsonString(result.columns[c])): \(value(c < row.count ? row[c] : nil, c))" }
            return "  {\n" + pairs.joined(separator: ",\n") + "\n  }"
        }
        return "[\n" + objects.joined(separator: ",\n") + "\n]\n"
    }

    static func markdown(_ result: QueryResult) -> String {
        func cell(_ v: String?) -> String { (v ?? "NULL").replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ") }
        var lines = ["| " + result.columns.map(cell).joined(separator: " | ") + " |"]
        lines.append("|" + result.columns.map { _ in " --- " }.joined(separator: "|") + "|")
        lines += result.rows.map { "| " + $0.map(cell).joined(separator: " | ") + " |" }
        return lines.joined(separator: "\n") + "\n"
    }

    static func jsonString(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 { out += String(format: "\\u%04x", scalar.value) } else { out.unicodeScalars.append(scalar) }
            }
        }
        return out + "\""
    }

    /// Shows a save panel and writes the file. Returns the URL that was written.
    @MainActor
    static func save(_ result: QueryResult, as format: ExportFormat, suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(suggestedName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try render(result, as: format).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            NSAlert(error: error).runModal()
            return nil
        }
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
