import SwiftUI

/// Column widths and numeric columns, computed once per data set (not on every redraw).
final class GridMetrics {
    private var signature: [Int] = []
    private(set) var widths: [CGFloat] = []
    private(set) var numeric: Set<Int> = []

    func prepare(columns: [String], types: [String], rows: [[String?]]) {
        let storage = rows.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
        let sig = [storage, rows.count, columns.count, columns.hashValue]
        guard sig != signature else { return }
        signature = sig
        widths = columns.indices.map { DataGrid.defaultWidth($0, columns: columns, types: types, rows: rows) }
        numeric = QueryResult(columns: columns, columnTypes: types, rows: Array(rows.prefix(60))).numericColumns()
    }
}

/// Spreadsheet-like grid used for table pages and for query results.
struct DataGrid: View {
    let columns: [String]
    var types: [String] = []
    let rows: [[String?]]
    var visible: [Int]?
    var rowOffset = 0
    var sort: SortSpec?
    var onSort: ((String) -> Void)?
    var editable = false
    var edits: [CellKey: String?] = [:]
    var deleted: Set<Int> = []
    var extraRows: [[String?]] = []
    var onEdit: ((CellKey, String?) -> Void)?
    var onToggleDelete: ((Int) -> Void)?
    var onFilter: ((String, String?, Bool) -> Void)?
    var onSelect: ((CellKey?) -> Void)?
    var compactRows: Int?

    @State private var metrics = GridMetrics()
    @State private var widthOverrides: [Int: CGFloat] = [:]
    @State private var dragBase: [Int: CGFloat] = [:]
    @State private var selected: CellKey?
    @State private var editing: CellKey?
    @State private var draft = ""
    @FocusState private var editorFocused: Bool
    @FocusState private var gridFocused: Bool
    @Environment(\.palette) private var palette

    static let rowHeight: CGFloat = 28
    static let numberWidth: CGFloat = 46

    private var shown: [Int] { visible ?? Array(columns.indices) }

    var body: some View {
        metrics.prepare(columns: columns, types: types, rows: rows)
        let shown = self.shown
        let widths = shown.map { width($0) }
        return Group {
            if let compactRows {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        header(shown, widths)
                        ForEach(0..<min(compactRows, rows.count), id: \.self) { r in
                            rowView(r, shown: shown, widths: widths)
                        }
                    }
                }
                .frame(height: Self.rowHeight + 6 + CGFloat(min(compactRows, rows.count)) * Self.rowHeight + 10)
            } else {
                NativeGrid(
                    columns: columns, types: types, rows: rows, visible: shown, widths: widths, numeric: metrics.numeric,
                    rowOffset: rowOffset, sort: sort, onSort: onSort, editable: editable && onEdit != nil,
                    edits: edits, deleted: deleted, extraRows: extraRows, onEdit: onEdit, onToggleDelete: onToggleDelete,
                    onFilter: onFilter, onSelect: onSelect, accent: NSColor(palette.accent)
                )
            }
        }
        .background(Theme.grid)
    }

    // MARK: Header

    private func header(_ shown: [Int], _ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            Text("#")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: Self.numberWidth, alignment: .trailing)
                .padding(.trailing, 6)
            ForEach(Array(shown.enumerated()), id: \.element) { i, c in
                GridHeaderCell(
                    name: columns[c],
                    type: c < types.count ? types[c] : "",
                    width: widths[i],
                    sort: sort?.column == columns[c] ? sort : nil,
                    sortable: onSort != nil,
                    onTap: { withAnimation(Theme.spring) { onSort?(columns[c]) } },
                    onResize: { translation, ended in
                        let base = dragBase[c] ?? width(c)
                        if dragBase[c] == nil { dragBase[c] = base }
                        widthOverrides[c] = max(48, base + translation)
                        if ended { dragBase[c] = nil }
                    }
                )
            }
        }
        .frame(height: Self.rowHeight + 6)
        .background(Theme.gridHeader)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.gridLine).frame(height: 1) }
    }

    // MARK: Rows

    private func rowView(_ r: Int, shown: [Int], widths: [CGFloat]) -> some View {
        var rowEdits: [Int: String?] = [:]
        if !edits.isEmpty {
            for (key, v) in edits where key.row == r { rowEdits[key.column] = v }
        }
        let isEditing = editing?.row == r
        return GridRowView(
            row: r,
            label: rowOffset + r + 1,
            values: rows[r],
            shown: shown,
            widths: widths,
            numeric: metrics.numeric,
            selectedColumn: selected?.row == r ? selected?.column : nil,
            editingColumn: isEditing ? editing?.column : nil,
            draft: isEditing ? $draft : .constant(""),
            editorFocused: $editorFocused,
            edits: rowEdits,
            deleted: deleted.contains(r),
            editable: editable && onEdit != nil,
            actions: GridRowActions(
                select: { key in
                    selected = key
                    gridFocused = true
                    onSelect?(key)
                },
                beginEdit: { beginEdit($0) },
                commitEdit: { commitEdit() },
                cancelEdit: { withAnimation(Theme.spring) { editing = nil } },
                menu: { key, v in AnyView(cellMenu(key, value: v)) }
            )
        )
        .equatable()
    }

    private func extraRow(_ i: Int, shown: [Int], widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.success)
                .frame(width: Self.numberWidth, alignment: .trailing)
                .padding(.trailing, 6)
            ForEach(Array(shown.enumerated()), id: \.element) { i2, c in
                let v = c < extraRows[i].count ? extraRows[i][c] : nil
                GridValueText(value: v, numeric: metrics.numeric.contains(c))
                    .padding(.horizontal, 8)
                    .frame(width: widths[i2], height: Self.rowHeight, alignment: metrics.numeric.contains(c) ? .trailing : .leading)
            }
        }
        .frame(height: Self.rowHeight)
        .background(Theme.success.opacity(0.12))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func value(_ key: CellKey) -> String? {
        if let e = edits[key] { return e }
        guard key.row < rows.count, key.column < rows[key.row].count else { return nil }
        return rows[key.row][key.column]
    }

    @ViewBuilder
    private func cellMenu(_ key: CellKey, value v: String?) -> some View {
        let name = columns[key.column]
        Button("Copy Value") { Exporter.copy(v ?? "NULL") }
        Button("Copy Row as JSON") { Exporter.copy(rowJSON(key.row)) }
        Button("Copy Column Name") { Exporter.copy(name) }
        if let onFilter {
            Divider()
            Button("Filter: \(name) = this value") { onFilter(name, v, false) }
            Button("Filter: \(name) ≠ this value") { onFilter(name, v, true) }
        }
        if editable, let onEdit {
            Divider()
            Button("Edit Cell") { beginEdit(key) }
            Button("Set NULL") { onEdit(key, nil) }
            if let onToggleDelete {
                Button(deleted.contains(key.row) ? "Restore Row" : "Delete Row", role: .destructive) { onToggleDelete(key.row) }
            }
        }
    }

    private func rowJSON(_ r: Int) -> String {
        let pairs = shown.map { c -> String in
            let v = value(CellKey(row: r, column: c))
            return "  \(Exporter.jsonString(columns[c])): \(v.map(Exporter.jsonString) ?? "null")"
        }
        return "{\n" + pairs.joined(separator: ",\n") + "\n}"
    }

    // MARK: Editing & keys

    private func beginEdit(_ key: CellKey) {
        guard editable, onEdit != nil, !deleted.contains(key.row) else { return }
        selected = key
        draft = value(key) ?? ""
        withAnimation(Theme.spring) { editing = key }
        DispatchQueue.main.async { editorFocused = true }
    }

    private func commitEdit() {
        guard let key = editing else { return }
        let original = value(key)
        if draft != (original ?? "") || original == nil && !draft.isEmpty {
            onEdit?(key, draft)
        }
        withAnimation(Theme.spring) { editing = nil }
        gridFocused = true
    }

    private func handleKey(_ key: KeyEquivalent) -> KeyPress.Result {
        guard editing == nil else { return .ignored }
        guard var s = selected else {
            if !rows.isEmpty, let first = shown.first {
                selected = CellKey(row: 0, column: first)
                onSelect?(selected)
            }
            return .handled
        }
        let cols = shown
        guard let ci = cols.firstIndex(of: s.column) else { return .ignored }
        switch key {
        case .upArrow: s.row = max(0, s.row - 1)
        case .downArrow: s.row = min(rows.count - 1, s.row + 1)
        case .leftArrow: s.column = cols[max(0, ci - 1)]
        case .rightArrow: s.column = cols[min(cols.count - 1, ci + 1)]
        case .return:
            beginEdit(s)
            return .handled
        default: return .ignored
        }
        selected = s
        onSelect?(s)
        return .handled
    }

    // MARK: Widths

    private func width(_ c: Int) -> CGFloat {
        if let w = widthOverrides[c] { return w }
        if c < metrics.widths.count { return metrics.widths[c] }
        return Self.defaultWidth(c, columns: columns, types: types, rows: rows)
    }

    /// Uses the UTF-8 byte count (constant time), so a 50 KB JSON cell costs as much as a short one.
    static func defaultWidth(_ c: Int, columns: [String], types: [String], rows: [[String?]]) -> CGFloat {
        var longest = columns[c].utf8.count + 2
        if c < types.count { longest = max(longest, types[c].utf8.count) }
        for row in rows.prefix(40) where c < row.count {
            longest = max(longest, min(row[c]?.utf8.count ?? 4, 48))
        }
        return min(max(CGFloat(longest) * 7.4 + 22, 64), 360)
    }

    /// Width of the whole grid with default column widths (row numbers included).
    static func estimatedWidth(columns: [String], types: [String], rows: [[String?]]) -> CGFloat {
        52 + columns.indices.reduce(0) { $0 + defaultWidth($1, columns: columns, types: types, rows: rows) } + 2
    }

    /// Text shown in a cell: long values are cut before any string work, new lines become ⏎.
    static func display(_ v: String) -> String {
        let short = v.utf8.count > 240 ? String(v.prefix(240)) + "…" : v
        guard short.contains(where: { $0 == "\n" || $0 == "\r" }) else { return short }
        return short.replacingOccurrences(of: "\r\n", with: " ⏎ ").replacingOccurrences(of: "\n", with: " ⏎ ").replacingOccurrences(of: "\r", with: " ")
    }
}

// MARK: - Row

struct GridRowActions {
    var select: (CellKey) -> Void
    var beginEdit: (CellKey) -> Void
    var commitEdit: () -> Void
    var cancelEdit: () -> Void
    var menu: (CellKey, String?) -> AnyView
}

/// One grid row. Equatable on its data only, so a row is redrawn only when its own data changed;
/// hover lives here, not in the grid.
struct GridRowView: View, Equatable {
    let row: Int
    let label: Int
    let values: [String?]
    let shown: [Int]
    let widths: [CGFloat]
    let numeric: Set<Int>
    let selectedColumn: Int?
    let editingColumn: Int?
    var draft: Binding<String>
    var editorFocused: FocusState<Bool>.Binding
    let edits: [Int: String?]
    let deleted: Bool
    let editable: Bool
    let actions: GridRowActions

    @State private var hover = false
    @State private var hoverColumn: Int?
    @Environment(\.palette) private var palette

    /// Column index (into `values`) under the x position, or nil over the row number.
    private func column(at x: CGFloat) -> Int? {
        var left = DataGrid.numberWidth + 6
        guard x >= left else { return nil }
        for (i, w) in widths.enumerated() {
            if x < left + w { return shown[i] }
            left += w
        }
        return nil
    }

    private func value(_ c: Int) -> String? {
        if let e = edits[c] { return e }
        return c < values.count ? values[c] : nil
    }

    static func == (a: GridRowView, b: GridRowView) -> Bool {
        a.row == b.row && a.label == b.label && a.values == b.values && a.shown == b.shown && a.widths == b.widths
            && a.numeric == b.numeric && a.selectedColumn == b.selectedColumn && a.editingColumn == b.editingColumn
            && a.edits == b.edits && a.deleted == b.deleted && a.editable == b.editable
            && (a.editingColumn == nil || a.draft.wrappedValue == b.draft.wrappedValue)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text("\(label)")
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(deleted ? Theme.danger : Theme.tertiaryText)
                .frame(width: DataGrid.numberWidth, alignment: .trailing)
                .padding(.trailing, 6)
            ForEach(Array(shown.enumerated()), id: \.element) { i, c in
                cell(column: c, width: widths[i])
            }
        }
        .frame(height: DataGrid.rowHeight)
        .background(background)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.gridLine.opacity(0.7)).frame(height: 0.5) }
        .overlay {
            if deleted {
                Rectangle().fill(Theme.danger.opacity(0.7)).frame(height: 1).padding(.leading, DataGrid.numberWidth + 6)
            }
        }
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            switch phase {
            case .active(let p):
                if !hover { hover = true }
                let c = column(at: p.x)
                if c != hoverColumn { hoverColumn = c }
            case .ended:
                hover = false
            }
        }
        .onTapGesture(count: 1, coordinateSpace: .local) { p in
            if let c = column(at: p.x) { actions.select(CellKey(row: row, column: c)) }
        }
        .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in
            if editable, let c = column(at: v.location.x) { actions.beginEdit(CellKey(row: row, column: c)) }
        })
        .contextMenu {
            if let c = hoverColumn {
                actions.menu(CellKey(row: row, column: c), value(c))
            }
        }
    }

    private var background: Color {
        if deleted { return Theme.danger.opacity(0.10) }
        if hover { return palette.accent.opacity(0.07) }
        return row % 2 == 1 ? Theme.gridStripe : Theme.grid
    }

    @ViewBuilder
    private func cell(column c: Int, width: CGFloat) -> some View {
        let isNumeric = numeric.contains(c)
        let edited = edits[c]
        let v: String? = edited ?? (c < values.count ? values[c] : nil)
        ZStack(alignment: isNumeric ? .trailing : .leading) {
            if editingColumn == c {
                TextField("", text: draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .focused(editorFocused)
                    .onSubmit { actions.commitEdit() }
                    .onExitCommand { actions.cancelEdit() }
                    .padding(.horizontal, 6)
                    .frame(height: DataGrid.rowHeight - 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.grid).shadow(color: palette.accent.opacity(0.35), radius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.accent, lineWidth: 1.5))
                    .padding(.horizontal, 2)
            } else {
                GridValueText(value: v, numeric: isNumeric)
                    .strikethrough(deleted, color: Theme.danger)
                    .padding(.horizontal, 8)
            }
        }
        .frame(width: width, height: DataGrid.rowHeight, alignment: isNumeric ? .trailing : .leading)
        .background(edited != nil ? Theme.edited.opacity(0.28) : .clear)
        .overlay {
            if selectedColumn == c && editingColumn != c {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(palette.accent, lineWidth: 1.5)
                    .padding(1)
            }
        }
    }
}

struct GridValueText: View {
    let value: String?
    let numeric: Bool

    var body: some View {
        if let value {
            Text(DataGrid.display(value))
                .font(.system(size: 12.5))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(numeric ? Theme.numeric : Theme.text)
        } else {
            Text("NULL")
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Capsule().stroke(Theme.tertiaryText.opacity(0.6), lineWidth: 0.8))
        }
    }
}

struct GridHeaderCell: View {
    let name: String
    let type: String
    let width: CGFloat
    let sort: SortSpec?
    let sortable: Bool
    let onTap: () -> Void
    let onResize: (CGFloat, Bool) -> Void

    @State private var hover = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                if !type.isEmpty {
                    Text(type.lowercased())
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.tertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let sort {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .rotationEffect(.degrees(sort.ascending ? 0 : 180))
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .frame(width: width, height: DataGrid.rowHeight + 6, alignment: .leading)
        .background(hover && sortable ? Theme.hover : .clear)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if sortable { onTap() } }
        .help(name)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 8)
                .overlay(Rectangle().fill(Theme.gridLine).frame(width: 1))
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                }
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { g in onResize(g.translation.width, false) }
                        .onEnded { g in onResize(g.translation.width, true) }
                )
        }
        .animation(Theme.spring, value: sort)
    }
}
