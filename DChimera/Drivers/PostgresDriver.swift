import Foundation
import Logging
import NIOCore
import NIOSSL
import PostgresNIO

/// PostgreSQL through PostgresNIO. PostgresNIO always asks the server for binary results,
/// so `PGValueFormatter` turns binary cells back into the text psql would print.
final actor PostgresDriver: DatabaseDriver {
    nonisolated let dialect: SQLDialect = .postgres
    private let connection: PostgresConnection
    private let logger: Logger

    private init(connection: PostgresConnection, logger: Logger) {
        self.connection = connection
        self.logger = logger
    }

    static func connect(_ config: ConnectionConfig, password: String?) async throws -> PostgresDriver {
        var logger = Logger(label: "dchimera.postgres")
        logger.logLevel = .error

        let tls: PostgresConnection.Configuration.TLS
        switch config.sslMode {
        case .disable:
            tls = .disable
        case .prefer, .require, .verifyFull:
            var tlsConfig = TLSConfiguration.makeClientConfiguration()
            if config.sslMode != .verifyFull { tlsConfig.certificateVerification = .none }
            let context = try NIOSSLContext(configuration: tlsConfig)
            tls = config.sslMode == .prefer ? .prefer(context) : .require(context)
        }

        var pg = PostgresConnection.Configuration(
            host: config.host.trimmingCharacters(in: .whitespaces),
            port: config.port,
            username: config.user,
            password: (password?.isEmpty ?? true) ? nil : password,
            database: config.database.isEmpty ? nil : config.database,
            tls: tls
        )
        pg.options.connectTimeout = .seconds(10)
        pg.options.additionalStartupParameters = [("application_name", "DChimera")]
        if config.readOnly {
            pg.options.additionalStartupParameters.append(("default_transaction_read_only", "on"))
        }
        do {
            let connection = try await PostgresConnection.connect(configuration: pg, id: Int.random(in: 1...999_999), logger: logger)
            return PostgresDriver(connection: connection, logger: logger)
        } catch {
            throw DBError.message(Self.describe(error))
        }
    }

    func close() async {
        try? await connection.close()
    }

    func serverVersion() async throws -> String {
        let v = try await strings("SHOW server_version").first ?? "?"
        return "PostgreSQL " + (v.split(separator: " ").first.map(String.init) ?? v)
    }

    func execute(_ sql: String, rowLimit: Int?) async throws -> QueryResult {
        let started = Date()
        do {
            var result: QueryResult
            if SQLText.returnsRows(sql) {
                result = try await readRows(sql, rowLimit: rowLimit)
            } else {
                let future: EventLoopFuture<PostgresQueryResult> = connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
                let out = try await future.get()
                result = QueryResult()
                if let first = out.rows.first {
                    var columns: [String] = []
                    var types: [String] = []
                    for cell in first {
                        columns.append(cell.columnName)
                        types.append(PGValueFormatter.typeName(cell.dataType))
                    }
                    result.columns = columns
                    result.columnTypes = types
                    result.rows = out.rows.prefix(rowLimit ?? Int.max).map { row in row.map(PGValueFormatter.format) }
                    result.truncated = rowLimit.map { out.rows.count > $0 } ?? false
                }
                result.message = out.metadata.command
                result.affectedRows = out.metadata.rows
            }
            result.duration = Date().timeIntervalSince(started)
            return result
        } catch {
            throw DBError.message(Self.describe(error))
        }
    }

    private func readRows(_ sql: String, rowLimit: Int?) async throws -> QueryResult {
        let sequence = try await connection.query(PostgresQuery(unsafeSQL: sql), logger: logger)
        var result = QueryResult()
        for column in sequence.columns {
            result.columns.append(column.name)
            result.columnTypes.append(PGValueFormatter.typeName(column.dataType))
        }
        for try await row in sequence {
            if let rowLimit, result.rows.count >= rowLimit {
                result.truncated = true
                continue // drain the rest so the connection stays usable
            }
            result.rows.append(row.map(PGValueFormatter.format))
        }
        return result
    }

    func listTables() async throws -> [TableRef] {
        let sql = """
        SELECT n.nspname, c.relname, c.relkind::text, GREATEST(c.reltuples, 0)::bigint
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind IN ('r','p','v','m','f')
          AND n.nspname NOT IN ('pg_catalog','information_schema')
          AND n.nspname NOT LIKE 'pg_toast%'
          AND n.nspname NOT LIKE 'pg_temp%'
          AND NOT c.relispartition
        ORDER BY n.nspname, c.relname
        """
        return try await execute(sql, rowLimit: nil).rows.map { row in
            let kind: TableRef.Kind = switch row[2] {
            case "v": .view
            case "m": .materializedView
            default: .table
            }
            return TableRef(schema: row[0] ?? "", name: row[1] ?? "", kind: kind, estimatedRows: row[3].flatMap { Int($0) })
        }
    }

    func listColumns() async throws -> [ColumnBrief] {
        let sql = """
        SELECT table_schema, table_name, column_name, data_type
        FROM information_schema.columns
        WHERE table_schema NOT IN ('pg_catalog','information_schema')
        ORDER BY table_schema, table_name, ordinal_position
        """
        return try await execute(sql, rowLimit: 50_000).rows.map {
            ColumnBrief(schema: $0[0] ?? "", table: $0[1] ?? "", column: $0[2] ?? "", type: $0[3] ?? "")
        }
    }

    func details(of table: TableRef) async throws -> TableDetails {
        let d = dialect
        let rel = d.literal(d.qualified(table))
        var details = TableDetails()

        let pk = Set(try await strings("""
        SELECT a.attname FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
        WHERE i.indrelid = \(rel)::regclass AND i.indisprimary
        """))

        let fkRows = try await execute("""
        SELECT con.conname,
               array_to_string(ARRAY(SELECT attname FROM pg_attribute WHERE attrelid = con.conrelid AND attnum = ANY(con.conkey)), ','),
               con.confrelid::regclass::text,
               array_to_string(ARRAY(SELECT attname FROM pg_attribute WHERE attrelid = con.confrelid AND attnum = ANY(con.confkey)), ',')
        FROM pg_constraint con
        WHERE con.conrelid = \(rel)::regclass AND con.contype = 'f'
        ORDER BY con.conname
        """, rowLimit: nil).rows
        var refs: [String: String] = [:]
        for row in fkRows {
            let cols = (row[1] ?? "").split(separator: ",").map(String.init)
            let refCols = (row[3] ?? "").split(separator: ",").map(String.init)
            let fk = ForeignKeyInfo(name: row[0] ?? "", columns: cols, refTable: row[2] ?? "", refColumns: refCols)
            details.foreignKeys.append(fk)
            for (i, c) in cols.enumerated() where i < refCols.count {
                refs[c] = "\(fk.refTable).\(refCols[i])"
            }
        }

        let cols = try await execute("""
        SELECT a.attname, format_type(a.atttypid, a.atttypmod), NOT a.attnotnull, pg_get_expr(ad.adbin, ad.adrelid)
        FROM pg_attribute a
        LEFT JOIN pg_attrdef ad ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
        WHERE a.attrelid = \(rel)::regclass AND a.attnum > 0 AND NOT a.attisdropped
        ORDER BY a.attnum
        """, rowLimit: nil).rows
        details.columns = cols.map { row in
            let name = row[0] ?? ""
            return ColumnInfo(name: name, type: row[1] ?? "", nullable: row[2] == "true",
                              defaultValue: row[3], isPrimaryKey: pk.contains(name), references: refs[name])
        }

        let idx = try await execute("""
        SELECT ic.relname, i.indisunique, i.indisprimary, pg_get_indexdef(i.indexrelid),
               array_to_string(ARRAY(SELECT pg_get_indexdef(i.indexrelid, k + 1, true) FROM generate_subscripts(i.indkey, 1) k ORDER BY k), ',')
        FROM pg_index i JOIN pg_class ic ON ic.oid = i.indexrelid
        WHERE i.indrelid = \(rel)::regclass
        ORDER BY i.indisprimary DESC, ic.relname
        """, rowLimit: nil).rows
        details.indexes = idx.map { row in
            IndexInfo(name: row[0] ?? "", columns: (row[4] ?? "").split(separator: ",").map(String.init),
                      unique: row[1] == "true", primary: row[2] == "true", definition: row[3])
        }

        if table.kind == .view || table.kind == .materializedView {
            let def = try await strings("SELECT pg_get_viewdef(\(rel)::regclass, true)").first ?? ""
            let word = table.kind == .view ? "VIEW" : "MATERIALIZED VIEW"
            details.ddl = "CREATE \(word) \(d.qualified(table)) AS\n\(def)"
        } else {
            var lines = details.columns.map { c -> String in
                var line = "  \(d.ident(c.name)) \(c.type)"
                if !c.nullable { line += " NOT NULL" }
                if let def = c.defaultValue { line += " DEFAULT \(def)" }
                return line
            }
            let cons = try await strings("""
            SELECT 'CONSTRAINT ' || quote_ident(conname) || ' ' || pg_get_constraintdef(oid)
            FROM pg_constraint WHERE conrelid = \(rel)::regclass ORDER BY contype DESC, conname
            """)
            lines += cons.map { "  " + $0 }
            var ddl = "CREATE TABLE \(d.qualified(table)) (\n" + lines.joined(separator: ",\n") + "\n);"
            let extra = details.indexes.filter { !$0.primary }.compactMap(\.definition)
            if !extra.isEmpty { ddl += "\n\n" + extra.map { $0 + ";" }.joined(separator: "\n") }
            details.ddl = ddl
        }
        return details
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? DBError { return e.localizedDescription }
        guard let e = error as? PSQLError else { return String(describing: error) }
        if let info = e.serverInfo, let message = info[.message] {
            var text = message
            if let detail = info[.detail] { text += "\nDETAIL: \(detail)" }
            if let hint = info[.hint] { text += "\nHINT: \(hint)" }
            if let position = info[.position] { text += "\nat character \(position)" }
            if let state = info[.sqlState] { text = "[\(state)] " + text }
            return text
        }
        if let underlying = e.underlying { return "\(e.code): \(underlying)" }
        return "\(e.code)"
    }
}

/// Turns binary PostgreSQL values into the text form psql prints.
enum PGValueFormatter {
    static func typeName(_ type: PostgresDataType) -> String {
        switch type.rawValue {
        case 16: "bool"
        case 17: "bytea"
        case 20: "int8"
        case 21: "int2"
        case 23: "int4"
        case 25: "text"
        case 26: "oid"
        case 114: "json"
        case 700: "float4"
        case 701: "float8"
        case 790: "money"
        case 1042: "bpchar"
        case 1043: "varchar"
        case 1082: "date"
        case 1083: "time"
        case 1114: "timestamp"
        case 1184: "timestamptz"
        case 1186: "interval"
        case 1700: "numeric"
        case 2950: "uuid"
        case 3802: "jsonb"
        default: type.description
        }
    }

    static func format(_ cell: PostgresCell) -> String? {
        guard var buffer = cell.bytes else { return nil }
        if cell.format == .text {
            return buffer.readString(length: buffer.readableBytes)
        }
        return format(oid: cell.dataType.rawValue, buffer: &buffer)
    }

    private static let pgEpoch: TimeInterval = 946_684_800 // 2000-01-01 UTC

    static func format(oid: UInt32, buffer: inout ByteBuffer) -> String {
        let n = buffer.readableBytes
        switch oid {
        case 16:
            return (buffer.readInteger(as: UInt8.self) ?? 0) != 0 ? "true" : "false"
        case 21:
            return buffer.readInteger(as: Int16.self).map { String($0) } ?? hex(&buffer)
        case 23:
            return buffer.readInteger(as: Int32.self).map { String($0) } ?? hex(&buffer)
        case 20:
            return buffer.readInteger(as: Int64.self).map { String($0) } ?? hex(&buffer)
        case 26, 24, 28, 29, 2202, 2203, 2204, 2205, 2206, 3734, 3769, 4089, 4096:
            return buffer.readInteger(as: UInt32.self).map { String($0) } ?? hex(&buffer)
        case 700:
            return buffer.readInteger(as: UInt32.self).map { formatDouble(Double(Float(bitPattern: $0))) } ?? hex(&buffer)
        case 701:
            return buffer.readInteger(as: UInt64.self).map { formatDouble(Double(bitPattern: $0)) } ?? hex(&buffer)
        case 790:
            guard let cents = buffer.readInteger(as: Int64.self) else { return hex(&buffer) }
            return String(format: "%.2f", Double(cents) / 100)
        case 1700:
            return numeric(&buffer) ?? hex(&buffer)
        case 17:
            return "\\x" + (buffer.readBytes(length: min(n, 256)) ?? []).map { String(format: "%02x", $0) }.joined() + (n > 256 ? "…" : "")
        case 3802:
            _ = buffer.readInteger(as: UInt8.self) // jsonb version byte
            return buffer.readString(length: buffer.readableBytes) ?? ""
        case 2950:
            guard let bytes = buffer.readBytes(length: 16) else { return hex(&buffer) }
            let h = bytes.map { String(format: "%02x", $0) }.joined()
            let parts = [h.prefix(8), h.dropFirst(8).prefix(4), h.dropFirst(12).prefix(4), h.dropFirst(16).prefix(4), h.dropFirst(20)]
            return parts.joined(separator: "-")
        case 1082:
            guard let days = buffer.readInteger(as: Int32.self) else { return hex(&buffer) }
            if days == Int32.max { return "infinity" }
            if days == Int32.min { return "-infinity" }
            return dateFormatter(utc: true, time: false).string(from: Date(timeIntervalSince1970: pgEpoch + Double(days) * 86_400))
        case 1083:
            guard let us = buffer.readInteger(as: Int64.self) else { return hex(&buffer) }
            return timeOfDay(us)
        case 1266:
            guard let us = buffer.readInteger(as: Int64.self), let zone = buffer.readInteger(as: Int32.self) else { return hex(&buffer) }
            let offset = -Int(zone)
            return timeOfDay(us) + String(format: "%@%02d", offset >= 0 ? "+" : "-", abs(offset) / 3600)
        case 1114, 1184:
            guard let us = buffer.readInteger(as: Int64.self) else { return hex(&buffer) }
            if us == Int64.max { return "infinity" }
            if us == Int64.min { return "-infinity" }
            let date = Date(timeIntervalSince1970: pgEpoch + Double(us) / 1_000_000)
            let fraction = ((us % 1_000_000) + 1_000_000) % 1_000_000
            var text = dateFormatter(utc: oid == 1114, time: true).string(from: date)
            if fraction != 0 {
                var f = String(format: "%06lld", fraction)
                while f.hasSuffix("0") { f.removeLast() }
                text += "." + f
            }
            if oid == 1184 {
                let seconds = TimeZone.current.secondsFromGMT(for: date)
                text += String(format: "%@%02d", seconds >= 0 ? "+" : "-", abs(seconds) / 3600)
                if abs(seconds) % 3600 != 0 { text += String(format: ":%02d", (abs(seconds) % 3600) / 60) }
            }
            return text
        case 1186:
            guard let us = buffer.readInteger(as: Int64.self),
                  let days = buffer.readInteger(as: Int32.self),
                  let months = buffer.readInteger(as: Int32.self) else { return hex(&buffer) }
            var parts: [String] = []
            if months / 12 != 0 { parts.append("\(months / 12) year\(abs(months / 12) == 1 ? "" : "s")") }
            if months % 12 != 0 { parts.append("\(months % 12) mon\(abs(months % 12) == 1 ? "" : "s")") }
            if days != 0 { parts.append("\(days) day\(abs(days) == 1 ? "" : "s")") }
            if us != 0 || parts.isEmpty { parts.append((us < 0 ? "-" : "") + timeOfDay(abs(us))) }
            return parts.joined(separator: " ")
        case 869, 650:
            return inet(&buffer) ?? hex(&buffer)
        case 829:
            return (buffer.readBytes(length: 6) ?? []).map { String(format: "%02x", $0) }.joined(separator: ":")
        case 600:
            guard let x = buffer.readInteger(as: UInt64.self), let y = buffer.readInteger(as: UInt64.self) else { return hex(&buffer) }
            return "(\(formatDouble(Double(bitPattern: x))),\(formatDouble(Double(bitPattern: y))))"
        case 1000, 1001, 1005, 1007, 1009, 1014, 1015, 1016, 1021, 1022, 1028, 1115, 1182, 1183, 1185, 1187, 1231, 1270, 2951, 3807, 199, 143, 1041, 651:
            return array(&buffer) ?? hex(&buffer)
        default:
            // text-like types (text, varchar, name, json, xml, enums, citext, ...) are sent as UTF-8 bytes
            let bytes = buffer.getBytes(at: buffer.readerIndex, length: n) ?? []
            if let s = String(bytes: bytes, encoding: .utf8), !s.contains("\u{0}") {
                return s
            }
            return hex(&buffer)
        }
    }

    private static func hex(_ buffer: inout ByteBuffer) -> String {
        let n = buffer.readableBytes
        let bytes = buffer.readBytes(length: min(n, 128)) ?? []
        return "\\x" + bytes.map { String(format: "%02x", $0) }.joined() + (n > 128 ? "…" : "")
    }

    private static func formatDouble(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d > 0 ? "Infinity" : "-Infinity" }
        if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
        return String(d)
    }

    private static func timeOfDay(_ us: Int64) -> String {
        let total = us / 1_000_000
        var text = String(format: "%02lld:%02lld:%02lld", total / 3600, (total % 3600) / 60, total % 60)
        let fraction = us % 1_000_000
        if fraction != 0 {
            var f = String(format: "%06lld", fraction)
            while f.hasSuffix("0") { f.removeLast() }
            text += "." + f
        }
        return text
    }

    private static let utcDate: DateFormatter = make("yyyy-MM-dd", utc: true)
    private static let utcDateTime: DateFormatter = make("yyyy-MM-dd HH:mm:ss", utc: true)
    private static let localDateTime: DateFormatter = make("yyyy-MM-dd HH:mm:ss", utc: false)

    private static func make(_ format: String, utc: Bool) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = utc ? TimeZone(identifier: "UTC") : TimeZone.current
        f.dateFormat = format
        return f
    }

    private static func dateFormatter(utc: Bool, time: Bool) -> DateFormatter {
        if !time { return utcDate }
        return utc ? utcDateTime : localDateTime
    }

    /// Binary numeric: ndigits, weight, sign, dscale, then base-10000 digits.
    private static func numeric(_ buffer: inout ByteBuffer) -> String? {
        guard let ndigits = buffer.readInteger(as: Int16.self),
              let weight = buffer.readInteger(as: Int16.self),
              let sign = buffer.readInteger(as: UInt16.self),
              let dscale = buffer.readInteger(as: Int16.self) else { return nil }
        if sign == 0xC000 { return "NaN" }
        if sign == 0xD000 { return "Infinity" }
        if sign == 0xF000 { return "-Infinity" }
        var digits: [Int16] = []
        for _ in 0..<Int(ndigits) {
            guard let d = buffer.readInteger(as: Int16.self) else { return nil }
            digits.append(d)
        }
        var intPart = ""
        if weight < 0 {
            intPart = "0"
        } else {
            for i in 0...Int(weight) {
                let d = i < digits.count ? digits[i] : 0
                intPart += i == 0 ? String(d) : String(format: "%04d", d)
            }
        }
        var fracPart = ""
        if dscale > 0 {
            var i = Int(weight) + 1
            while fracPart.count < Int(dscale) {
                let d: Int16 = (i >= 0 && i < digits.count) ? digits[i] : 0
                fracPart += String(format: "%04d", d)
                i += 1
            }
            fracPart = String(fracPart.prefix(Int(dscale)))
        }
        let body = fracPart.isEmpty ? intPart : intPart + "." + fracPart
        return (sign == 0x4000 ? "-" : "") + body
    }

    private static func inet(_ buffer: inout ByteBuffer) -> String? {
        guard let family = buffer.readInteger(as: UInt8.self),
              let bits = buffer.readInteger(as: UInt8.self),
              let isCidr = buffer.readInteger(as: UInt8.self),
              let count = buffer.readInteger(as: UInt8.self),
              let bytes = buffer.readBytes(length: Int(count)) else { return nil }
        let address: String
        if family == 2 || count == 4 {
            address = bytes.map(String.init).joined(separator: ".")
        } else {
            var groups: [String] = []
            for i in stride(from: 0, to: bytes.count - 1, by: 2) {
                groups.append(String(format: "%x", UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])))
            }
            address = groups.joined(separator: ":")
        }
        let full = (family == 2 || count == 4) ? 32 : 128
        return Int(bits) == full && isCidr == 0 ? address : "\(address)/\(bits)"
    }

    private static func array(_ buffer: inout ByteBuffer) -> String? {
        guard let ndim = buffer.readInteger(as: Int32.self),
              buffer.readInteger(as: Int32.self) != nil,
              let elementType = buffer.readInteger(as: UInt32.self) else { return nil }
        if ndim == 0 { return "{}" }
        var dims: [Int] = []
        for _ in 0..<Int(ndim) {
            guard let len = buffer.readInteger(as: Int32.self), buffer.readInteger(as: Int32.self) != nil else { return nil }
            dims.append(Int(len))
        }
        func element() -> String? {
            guard let len = buffer.readInteger(as: Int32.self) else { return nil }
            if len < 0 { return "NULL" }
            guard var slice = buffer.readSlice(length: Int(len)) else { return nil }
            let text = format(oid: elementType, buffer: &slice)
            let needsQuotes = text.isEmpty || text.contains(where: { ",{}\" \\".contains($0) }) || text.uppercased() == "NULL"
            return needsQuotes ? "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" : text
        }
        func level(_ d: Int) -> String? {
            var items: [String] = []
            for _ in 0..<dims[d] {
                guard let item = d == dims.count - 1 ? element() : level(d + 1) else { return nil }
                items.append(item)
            }
            return "{" + items.joined(separator: ",") + "}"
        }
        return level(0)
    }
}
