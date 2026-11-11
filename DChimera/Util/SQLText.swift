import Foundation

/// Tokenizer and statement helpers shared by the editor, the bubbles and the drivers.
enum SQLText {
    enum TokenKind {
        case keyword, string, number, comment, quotedIdent, function, param, identifier, punct
    }

    struct Token {
        var kind: TokenKind
        var range: NSRange
    }

    static let keywords: Set<String> = [
        "ADD", "ALL", "ALTER", "ANALYZE", "AND", "ANY", "ARRAY", "AS", "ASC", "BEGIN", "BETWEEN", "BIGINT", "BOOLEAN", "BOTH", "BY",
        "CASCADE", "CASE", "CAST", "CHECK", "COLLATE", "COLUMN", "COMMIT", "CONFLICT", "CONSTRAINT", "COPY", "CREATE", "CROSS",
        "CURRENT_DATE", "CURRENT_TIME", "CURRENT_TIMESTAMP", "DATABASE", "DEFAULT", "DELETE", "DESC", "DESCRIBE", "DISTINCT", "DO",
        "DROP", "ELSE", "END", "ESCAPE", "EXCEPT", "EXISTS", "EXPLAIN", "FALSE", "FETCH", "FILTER", "FIRST", "FOR", "FOREIGN",
        "FROM", "FULL", "FUNCTION", "GRANT", "GROUP", "HAVING", "IF", "ILIKE", "IN", "INDEX", "INNER", "INSERT", "INTEGER",
        "INTERSECT", "INTERVAL", "INTO", "IS", "JOIN", "KEY", "LAST", "LATERAL", "LEFT", "LIKE", "LIMIT", "MATERIALIZED",
        "NATURAL", "NOT", "NOTHING", "NULL", "NULLS", "OFFSET", "ON", "ONLY", "OR", "ORDER", "OUTER", "OVER", "PARTITION",
        "PRIMARY", "PRAGMA", "RECURSIVE", "REFERENCES", "RENAME", "REPLACE", "RETURNING", "REVOKE", "RIGHT", "ROLLBACK", "ROW",
        "ROWS", "SCHEMA", "SELECT", "SET", "SHOW", "SOME", "TABLE", "TEXT", "THEN", "TO", "TRUE", "TRUNCATE", "UNION",
        "UNIQUE", "UPDATE", "USING", "VACUUM", "VALUES", "VARCHAR", "VIEW", "WHEN", "WHERE", "WINDOW", "WITH", "WITHOUT",
    ]

    static let functions: [String] = [
        "count", "sum", "avg", "min", "max", "coalesce", "nullif", "lower", "upper", "length", "substring", "trim",
        "now", "date_trunc", "extract", "to_char", "round", "abs", "concat", "string_agg", "array_agg", "json_agg",
        "jsonb_build_object", "row_number", "rank", "dense_rank", "lag", "lead", "greatest", "least", "random",
        "strftime", "datetime", "date", "group_concat", "ifnull", "date_format",
    ]

    // MARK: Tokenizer

    static func tokenize(_ text: NSString) -> [Token] {
        let n = text.length
        var tokens: [Token] = []
        var chars = [unichar](repeating: 0, count: n)
        text.getCharacters(&chars, range: NSRange(location: 0, length: n))

        func isIdentStart(_ c: unichar) -> Bool {
            (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
        }
        func isIdent(_ c: unichar) -> Bool { isIdentStart(c) || (c >= 48 && c <= 57) || c == 36 }
        func isDigit(_ c: unichar) -> Bool { c >= 48 && c <= 57 }

        var i = 0
        while i < n {
            let c = chars[i]
            let next: unichar = i + 1 < n ? chars[i + 1] : 0
            let start = i
            if c == 45, next == 45 { // --
                while i < n, chars[i] != 10 { i += 1 }
                tokens.append(Token(kind: .comment, range: NSRange(location: start, length: i - start)))
            } else if c == 35, i + 1 < n, chars[i + 1] == 32 || chars[i + 1] == 9 { // "# " MySQL comment
                while i < n, chars[i] != 10 { i += 1 }
                tokens.append(Token(kind: .comment, range: NSRange(location: start, length: i - start)))
            } else if c == 47, next == 42 { // /* */
                i += 2
                while i < n, !(chars[i] == 42 && i + 1 < n && chars[i + 1] == 47) { i += 1 }
                i = min(n, i + 2)
                tokens.append(Token(kind: .comment, range: NSRange(location: start, length: i - start)))
            } else if c == 39 { // '
                i += 1
                while i < n {
                    if chars[i] == 39 {
                        if i + 1 < n, chars[i + 1] == 39 { i += 2; continue }
                        i += 1
                        break
                    }
                    if chars[i] == 92, i + 1 < n { i += 2; continue } // backslash escapes (MySQL / E'')
                    i += 1
                }
                tokens.append(Token(kind: .string, range: NSRange(location: start, length: i - start)))
            } else if c == 34 || c == 96 { // " or `
                i += 1
                while i < n, chars[i] != c { i += 1 }
                i = min(n, i + 1)
                tokens.append(Token(kind: .quotedIdent, range: NSRange(location: start, length: i - start)))
            } else if c == 36, isDigit(next) { // $1
                i += 1
                while i < n, isDigit(chars[i]) { i += 1 }
                tokens.append(Token(kind: .param, range: NSRange(location: start, length: i - start)))
            } else if c == 36, next == 36 || isIdentStart(next) { // $tag$ ... $tag$
                var j = i + 1
                while j < n, chars[j] != 36, isIdent(chars[j]) { j += 1 }
                if j < n, chars[j] == 36 {
                    let tag = Array(chars[i...j])
                    i = j + 1
                    var closed = false
                    while i < n {
                        if chars[i] == 36, i + tag.count <= n, Array(chars[i..<(i + tag.count)]) == tag {
                            i += tag.count
                            closed = true
                            break
                        }
                        i += 1
                    }
                    _ = closed
                    tokens.append(Token(kind: .string, range: NSRange(location: start, length: i - start)))
                } else {
                    i += 1
                }
            } else if isDigit(c) || (c == 46 && isDigit(next)) {
                while i < n, isDigit(chars[i]) || chars[i] == 46 { i += 1 }
                if i < n, chars[i] == 101 || chars[i] == 69 {
                    i += 1
                    if i < n, chars[i] == 43 || chars[i] == 45 { i += 1 }
                    while i < n, isDigit(chars[i]) { i += 1 }
                }
                tokens.append(Token(kind: .number, range: NSRange(location: start, length: i - start)))
            } else if isIdentStart(c) {
                while i < n, isIdent(chars[i]) { i += 1 }
                let range = NSRange(location: start, length: i - start)
                let word = text.substring(with: range).uppercased()
                var j = i
                while j < n, chars[j] == 32 { j += 1 }
                let prev: unichar = start > 0 ? chars[start - 1] : 0
                if keywords.contains(word) && prev != 46 {
                    tokens.append(Token(kind: .keyword, range: range))
                } else if j < n, chars[j] == 40 {
                    tokens.append(Token(kind: .function, range: range))
                } else {
                    tokens.append(Token(kind: .identifier, range: range))
                }
            } else if c == 58, isIdentStart(next), start == 0 || chars[start - 1] != 58 { // :name
                i += 1
                while i < n, isIdent(chars[i]) { i += 1 }
                tokens.append(Token(kind: .param, range: NSRange(location: start, length: i - start)))
            } else {
                i += 1
                if c != 32 && c != 10 && c != 9 && c != 13 {
                    tokens.append(Token(kind: .punct, range: NSRange(location: start, length: 1)))
                }
            }
        }
        return tokens
    }

    // MARK: Statements

    /// Ranges of the statements in `text`, split on `;` outside strings and comments. Empty statements are dropped.
    static func statementRanges(_ text: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var start = 0
        for token in tokenize(text) where token.kind == .punct {
            if text.character(at: token.range.location) == 59 {
                ranges.append(NSRange(location: start, length: token.range.location - start))
                start = token.range.location + 1
            }
        }
        ranges.append(NSRange(location: start, length: text.length - start))
        return ranges.filter { !isBlank(text.substring(with: $0)) }
    }

    static func statements(_ sql: String) -> [String] {
        let ns = sql as NSString
        return statementRanges(ns).map { ns.substring(with: $0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// The statement under the cursor (or the nearest one before it).
    static func statement(at location: Int, in text: NSString) -> NSRange? {
        let ranges = statementRanges(text)
        if let hit = ranges.first(where: { location >= $0.location && location <= $0.location + $0.length + 1 }) {
            return hit
        }
        return ranges.last(where: { $0.location <= location }) ?? ranges.first
    }

    /// True when the text has nothing but whitespace and comments.
    static func isBlank(_ sql: String) -> Bool {
        tokenize(sql as NSString).allSatisfy { $0.kind == .comment }
    }

    static func firstKeyword(_ sql: String) -> String {
        let ns = sql as NSString
        guard let token = tokenize(ns).first(where: { $0.kind != .comment && $0.kind != .punct }) else { return "" }
        return ns.substring(with: token.range).lowercased()
    }

    /// Statements that answer with rows, so the driver reads columns and rows.
    static func returnsRows(_ sql: String) -> Bool {
        ["select", "with", "values", "table", "show", "explain", "pragma", "describe", "desc"].contains(firstKeyword(sql))
            && !hasDataModifyingCTE(sql)
    }

    private static func hasDataModifyingCTE(_ sql: String) -> Bool {
        guard firstKeyword(sql) == "with" else { return false }
        let ns = sql as NSString
        return tokenize(ns).contains { $0.kind == .keyword && ["INSERT", "UPDATE", "DELETE"].contains(ns.substring(with: $0.range).uppercased()) }
    }

    /// Wraps a plain SELECT so the server sends at most `limit + 1` rows.
    static func limited(_ sql: String, limit: Int) -> String? {
        let first = firstKeyword(sql)
        guard first == "select" || first == "with" || first == "values", !hasDataModifyingCTE(sql) else { return nil }
        let ns = sql as NSString
        let words = tokenize(ns).filter { $0.kind == .keyword }.map { ns.substring(with: $0.range).uppercased() }
        if words.contains("INTO") || (words.contains("FOR") && words.contains("UPDATE")) { return nil }
        var body = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while body.hasSuffix(";") { body.removeLast() }
        return "SELECT * FROM (\n\(body)\n) AS dchimera_rows LIMIT \(limit + 1)"
    }

    /// A reason to ask before running, or nil when the statement looks harmless.
    static func dangerReason(_ sql: String) -> String? {
        let ns = sql as NSString
        let tokens = tokenize(ns)
        let words = tokens.filter { $0.kind == .keyword || $0.kind == .identifier }.map { ns.substring(with: $0.range).uppercased() }
        guard let first = words.first else { return nil }
        switch first {
        case "DROP": return "DROP removes the object and its data."
        case "TRUNCATE": return "TRUNCATE deletes every row of the table."
        case "DELETE" where !words.contains("WHERE"): return "DELETE without WHERE removes every row."
        case "UPDATE" where !words.contains("WHERE"): return "UPDATE without WHERE changes every row."
        case "ALTER": return "ALTER changes the structure of the table."
        default: return nil
        }
    }

    /// One-line preview used in the chat list.
    static func preview(_ sql: String) -> String {
        sql.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }
}
