import AppKit
import SwiftUI

/// Colors of the grid as NSColor (same values as Theme).
enum GridColors {
    static func dynamic(_ light: UInt32, _ dark: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
    }

    static var background: NSColor { Skin.current.grid.ns }
    static var stripe: NSColor { Skin.current.gridStripe.ns }
    static var header: NSColor { Skin.current.gridHeader.ns }
    static var line: NSColor { Skin.current.gridLine.ns }
    static var tertiary: NSColor { Skin.current.tertiary.ns }
    static var numeric: NSColor { Skin.current.numeric.ns }
    static var text: NSColor { Skin.current.nsText }
    static var font: NSFont { Skin.current.gridFont }
    static let edited = NSColor(srgbRed: 0xF5 / 255.0, green: 0xC5 / 255.0, blue: 0x42 / 255.0, alpha: 0.28)
    static let danger = NSColor(srgbRed: 0xEF / 255.0, green: 0x5B / 255.0, blue: 0x5B / 255.0, alpha: 1)
    static let success = NSColor(srgbRed: 0x3C / 255.0, green: 0xC4 / 255.0, blue: 0x7C / 255.0, alpha: 1)
}

/// The full-size grid, backed by NSTableView: only visible rows get views, and row views are reused while scrolling.
struct NativeGrid: NSViewRepresentable {
    var columns: [String]
    var types: [String]
    var rows: [[String?]]
    var visible: [Int]
    var widths: [CGFloat]
    var numeric: Set<Int>
    var rowOffset: Int
    var sort: SortSpec?
    var onSort: ((String) -> Void)?
    var editable: Bool
    var edits: [CellKey: String?]
    var deleted: Set<Int>
    var extraRows: [[String?]]
    var onEdit: ((CellKey, String?) -> Void)?
    var onToggleDelete: ((Int) -> Void)?
    var onFilter: ((String, String?, Bool) -> Void)?
    var onSelect: ((CellKey?) -> Void)?
    var accent: NSColor

    func makeCoordinator() -> NativeGridController { NativeGridController() }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.apply(self, force: true)
        return context.coordinator.scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.apply(self, force: false)
    }
}

final class NativeGridController: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate {
    let scrollView = NSScrollView()
    let tableView = GridTableView()
    private(set) var config: NativeGrid?
    var selected: CellKey?
    private var editor: NSTextField?
    private var editingKey: CellKey?
    private var columnSignature: [String] = []
    private var dataSignature: [Int] = []

    override init() {
        super.init()
        tableView.controller = self
        tableView.dataSource = self
        tableView.delegate = self
        tableView.headerView = GridHeaderView(frame: NSRect(x: 0, y: 0, width: 0, height: 34))
        tableView.rowHeight = DataGrid.rowHeight
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = [.solidHorizontalGridLineMask]
        tableView.gridColor = GridColors.line
        tableView.backgroundColor = GridColors.background
        tableView.selectionHighlightStyle = .none
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.usesAutomaticRowHeights = false
        tableView.style = .plain
        tableView.target = self
        tableView.doubleAction = #selector(doubleClicked)
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = GridColors.background
        scrollView.borderType = .noBorder
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 70, right: 0)
    }

    // MARK: Updates from SwiftUI

    func apply(_ grid: NativeGrid, force: Bool) {
        let previous = config
        config = grid
        let colSig = grid.visible.map { "\($0):\(grid.columns[$0])" }
        if force || colSig != columnSignature {
            columnSignature = colSig
            rebuildColumns(grid)
            selected = nil
        }
        let storage = grid.rows.withUnsafeBufferPointer { Int(bitPattern: $0.baseAddress) }
        let dataSig = [storage, grid.rows.count, grid.extraRows.count, grid.rowOffset]
        let editsChanged = previous.map { $0.edits != grid.edits || $0.deleted != grid.deleted || $0.editable != grid.editable } ?? true
        if force || dataSig != dataSignature || editsChanged {
            if dataSig != dataSignature { selected = nil; cancelEdit() }
            dataSignature = dataSig
            tableView.reloadData()
        }
        if force || previous?.sort != grid.sort {
            for column in tableView.tableColumns {
                guard let c = dataIndex(column) else { continue }
                let cell = column.headerCell as? NativeHeaderCell
                cell?.sortAscending = grid.sort?.column == grid.columns[c] ? grid.sort?.ascending : nil
            }
            tableView.headerView?.needsDisplay = true
        }
        tableView.accent = grid.accent
    }

    private func rebuildColumns(_ grid: NativeGrid) {
        for column in tableView.tableColumns.reversed() { tableView.removeTableColumn(column) }
        let number = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("#"))
        number.width = DataGrid.numberWidth + 6
        number.minWidth = 36
        number.resizingMask = []
        let numberHeader = NativeHeaderCell(textCell: "#")
        numberHeader.alignment = .right
        number.headerCell = numberHeader
        tableView.addTableColumn(number)
        for (i, c) in grid.visible.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c\(c)"))
            column.width = i < grid.widths.count ? grid.widths[i] : 120
            column.minWidth = 48
            column.maxWidth = 2000
            column.resizingMask = .userResizingMask
            let header = NativeHeaderCell(textCell: grid.columns[c])
            header.typeName = c < grid.types.count ? grid.types[c] : ""
            column.headerCell = header
            column.headerToolTip = grid.columns[c] + (header.typeName.isEmpty ? "" : " · \(header.typeName)")
            tableView.addTableColumn(column)
        }
    }

    func dataIndex(_ column: NSTableColumn) -> Int? {
        let id = column.identifier.rawValue
        guard id.hasPrefix("c") else { return nil }
        return Int(id.dropFirst())
    }

    func dataIndex(tableColumn index: Int) -> Int? {
        guard index >= 0, index < tableView.tableColumns.count else { return nil }
        return dataIndex(tableView.tableColumns[index])
    }

    func value(_ key: CellKey) -> String? {
        guard let g = config else { return nil }
        if let e = g.edits[key] { return e }
        if key.row < g.rows.count {
            let row = g.rows[key.row]
            return key.column < row.count ? row[key.column] : nil
        }
        let extra = key.row - g.rows.count
        guard extra < g.extraRows.count, key.column < g.extraRows[extra].count else { return nil }
        return g.extraRows[extra][key.column]
    }

    // MARK: Data source & delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        guard let g = config else { return 0 }
        return g.rows.count + g.extraRows.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let g = config, let tableColumn else { return nil }
        let id = NSUserInterfaceItemIdentifier("cell")
        let view = (tableView.makeView(withIdentifier: id, owner: nil) as? GridCellView) ?? {
            let v = GridCellView()
            v.identifier = id
            return v
        }()
        let isExtra = row >= g.rows.count
        if let c = dataIndex(tableColumn) {
            let key = CellKey(row: row, column: c)
            view.configure(text: value(key), isNull: value(key) == nil, numeric: g.numeric.contains(c),
                           edited: !isExtra && g.edits[key] != nil, deleted: !isExtra && g.deleted.contains(row),
                           selected: selected == key, accent: g.accent, rowNumber: false)
        } else {
            view.configure(text: isExtra ? "+" : "\(g.rowOffset + row + 1)", isNull: false, numeric: true, edited: false,
                           deleted: !isExtra && g.deleted.contains(row), selected: false, accent: g.accent, rowNumber: true)
        }
        return view
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let view = (tableView.makeView(withIdentifier: id, owner: nil) as? GridRowBackground) ?? {
            let v = GridRowBackground()
            v.identifier = id
            return v
        }()
        guard let g = config else { return view }
        view.stripe = row % 2 == 1
        view.deleted = row < g.rows.count && g.deleted.contains(row)
        view.extra = row >= g.rows.count
        view.hovered = (tableView as? GridTableView)?.hoverRow == row
        view.accent = g.accent
        return view
    }

    func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
        guard let g = config, let onSort = g.onSort, let c = dataIndex(tableColumn) else { return }
        onSort(g.columns[c])
    }

    // MARK: Cell selection

    func select(_ key: CellKey?, scroll: Bool = false) {
        let old = selected
        selected = key
        for k in [old, key].compactMap({ $0 }) { refresh(k) }
        if scroll, let key {
            tableView.scrollRowToVisible(key.row)
            if let col = tableView.tableColumns.firstIndex(where: { dataIndex($0) == key.column }) {
                tableView.scrollColumnToVisible(col)
            }
        }
        config?.onSelect?(key)
    }

    private func refresh(_ key: CellKey) {
        guard key.row < tableView.numberOfRows,
              let col = tableView.tableColumns.firstIndex(where: { dataIndex($0) == key.column }) else { return }
        tableView.reloadData(forRowIndexes: IndexSet(integer: key.row), columnIndexes: IndexSet(integer: col))
    }

    func moveSelection(dx: Int, dy: Int) {
        guard let g = config, !g.visible.isEmpty else { return }
        guard var key = selected else {
            select(CellKey(row: 0, column: g.visible[0]), scroll: true)
            return
        }
        key.row = min(max(0, key.row + dy), max(0, numberOfRows(in: tableView) - 1))
        if dx != 0, let i = g.visible.firstIndex(of: key.column) {
            key.column = g.visible[min(max(0, i + dx), g.visible.count - 1)]
        }
        select(key, scroll: true)
    }

    // MARK: Editing

    @objc func doubleClicked() {
        let row = tableView.clickedRow, col = tableView.clickedColumn
        guard row >= 0, let c = dataIndex(tableColumn: col) else { return }
        beginEdit(CellKey(row: row, column: c))
    }

    func beginEdit(_ key: CellKey) {
        guard let g = config, g.editable, g.onEdit != nil, key.row < g.rows.count, !g.deleted.contains(key.row),
              let col = tableView.tableColumns.firstIndex(where: { dataIndex($0) == key.column }) else { return }
        cancelEdit()
        select(key, scroll: true)
        let rect = tableView.frameOfCell(atColumn: col, row: key.row).insetBy(dx: 2, dy: 2)
        let field = NSTextField(frame: rect)
        field.stringValue = value(key) ?? ""
        field.font = .systemFont(ofSize: 12.5)
        field.isBordered = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
        field.wantsLayer = true
        field.layer?.borderColor = g.accent.cgColor
        field.layer?.borderWidth = 1.5
        field.layer?.cornerRadius = 6
        tableView.addSubview(field)
        editor = field
        editingKey = key
        tableView.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func commitEdit() {
        guard let field = editor, let key = editingKey else { return }
        let text = field.stringValue
        let original = value(key)
        editor = nil
        editingKey = nil
        field.removeFromSuperview()
        if text != (original ?? "") || (original == nil && !text.isEmpty) {
            config?.onEdit?(key, text)
        }
        tableView.window?.makeFirstResponder(tableView)
    }

    func cancelEdit() {
        guard let field = editor else { return }
        editor = nil
        editingKey = nil
        field.removeFromSuperview()
        tableView.window?.makeFirstResponder(tableView)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) { commitEdit(); return true }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelEdit(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if editor != nil { commitEdit() }
    }

    // MARK: Context menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let g = config else { return }
        let row = tableView.clickedRow
        guard row >= 0, let c = dataIndex(tableColumn: tableView.clickedColumn) else { return }
        let key = CellKey(row: row, column: c)
        select(key)
        let v = value(key)
        let name = g.columns[c]
        func item(_ title: String, _ action: @escaping () -> Void) {
            let it = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
            let box = MenuAction(action)
            it.target = box
            it.representedObject = box
            menu.addItem(it)
        }
        item("Copy Value") { Exporter.copy(v ?? "NULL") }
        item("Copy Row as JSON") { [weak self] in Exporter.copy(self?.rowJSON(row) ?? "") }
        item("Copy Column Name") { Exporter.copy(name) }
        if let onFilter = g.onFilter {
            menu.addItem(.separator())
            item("Filter: \(name) = this value") { onFilter(name, v, false) }
            item("Filter: \(name) ≠ this value") { onFilter(name, v, true) }
        }
        if g.editable, let onEdit = g.onEdit, row < g.rows.count {
            menu.addItem(.separator())
            item("Edit Cell") { [weak self] in self?.beginEdit(key) }
            item("Set NULL") { onEdit(key, nil) }
            if let onToggleDelete = g.onToggleDelete {
                item(g.deleted.contains(row) ? "Restore Row" : "Delete Row") { onToggleDelete(row) }
            }
        }
    }

    func rowJSON(_ row: Int) -> String {
        guard let g = config else { return "" }
        let pairs = g.visible.map { c -> String in
            let v = value(CellKey(row: row, column: c))
            return "  \(Exporter.jsonString(g.columns[c])): \(v.map(Exporter.jsonString) ?? "null")"
        }
        return "{\n" + pairs.joined(separator: ",\n") + "\n}"
    }
}

/// Keeps a closure alive for an NSMenuItem.
final class MenuAction: NSObject {
    let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

// MARK: - Table view

final class GridTableView: NSTableView {
    weak var controller: NativeGridController?
    var accent: NSColor = .controlAccentColor
    private(set) var hoverRow = -1
    private var hoverArea: NSTrackingArea?

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let row = self.row(at: p), col = column(at: p)
        if row >= 0, let c = controller?.dataIndex(tableColumn: col) {
            controller?.select(CellKey(row: row, column: c))
        }
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard let controller else { return super.keyDown(with: event) }
        switch event.keyCode {
        case 123: controller.moveSelection(dx: -1, dy: 0)
        case 124: controller.moveSelection(dx: 1, dy: 0)
        case 125: controller.moveSelection(dx: 0, dy: 1)
        case 126: controller.moveSelection(dx: 0, dy: -1)
        case 36, 76:
            if let key = controller.selected { controller.beginEdit(key) }
        default: super.keyDown(with: event)
        }
    }

    @objc func copy(_ sender: Any?) {
        guard let controller, let key = controller.selected else { return }
        Exporter.copy(controller.value(key) ?? "NULL")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        setHover(row(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        setHover(-1)
    }

    private func setHover(_ row: Int) {
        guard row != hoverRow else { return }
        let old = hoverRow
        hoverRow = row
        for r in [old, row] where r >= 0 && r < numberOfRows {
            if let view = rowView(atRow: r, makeIfNecessary: false) as? GridRowBackground {
                view.hovered = r == row
            }
        }
    }
}

final class GridRowBackground: NSTableRowView {
    var stripe = false { didSet { if oldValue != stripe { needsDisplay = true } } }
    var deleted = false { didSet { if oldValue != deleted { needsDisplay = true } } }
    var extra = false { didSet { if oldValue != extra { needsDisplay = true } } }
    var hovered = false { didSet { if oldValue != hovered { needsDisplay = true } } }
    var accent: NSColor = .controlAccentColor

    override func drawBackground(in dirtyRect: NSRect) {
        let color: NSColor
        if deleted { color = GridColors.danger.withAlphaComponent(0.10) }
        else if extra { color = GridColors.success.withAlphaComponent(0.12) }
        else if hovered { color = accent.withAlphaComponent(0.08) }
        else { color = stripe ? GridColors.stripe : GridColors.background }
        color.setFill()
        dirtyRect.fill()
        if deleted {
            GridColors.danger.withAlphaComponent(0.7).setFill()
            NSRect(x: DataGrid.numberWidth + 6, y: bounds.midY, width: bounds.width, height: 1).fill()
        }
    }

    override func drawSelection(in dirtyRect: NSRect) {}
}

/// One cell, drawn directly (no text field), so creating and reusing it is cheap.
final class GridCellView: NSView {
    private var text: String?
    private var isNull = false
    private var numeric = false
    private var edited = false
    private var deleted = false
    private var selectedCell = false
    private var rowNumber = false
    private var accent: NSColor = .controlAccentColor

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    func configure(text: String?, isNull: Bool, numeric: Bool, edited: Bool, deleted: Bool, selected: Bool, accent: NSColor, rowNumber: Bool) {
        self.text = text.map(DataGrid.display)
        self.isNull = isNull
        self.numeric = numeric
        self.edited = edited
        self.deleted = deleted
        self.selectedCell = selected
        self.accent = accent
        self.rowNumber = rowNumber
        needsDisplay = true
    }

    private static let paragraphLeft: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        p.alignment = .left
        return p
    }()

    private static let paragraphRight: NSParagraphStyle = {
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byTruncatingTail
        p.alignment = .right
        return p
    }()

    private static let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
    private static let nullFont = NSFont.systemFont(ofSize: 9.5, weight: .bold)

    override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        if edited {
            GridColors.edited.setFill()
            b.fill()
        }
        if rowNumber {
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.numberFont, .foregroundColor: deleted ? GridColors.danger : GridColors.tertiary,
                                                        .paragraphStyle: Self.paragraphRight]
            (text ?? "").draw(with: NSRect(x: 0, y: (b.height - 13) / 2, width: b.width - 8, height: 14),
                              options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
            return
        }
        if isNull {
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.nullFont, .foregroundColor: GridColors.tertiary]
            let size = ("NULL" as NSString).size(withAttributes: attrs)
            let pill = NSRect(x: numeric ? b.width - size.width - 18 : 8, y: (b.height - size.height - 3) / 2, width: size.width + 10, height: size.height + 3)
            let path = NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2)
            GridColors.tertiary.withAlphaComponent(0.6).setStroke()
            path.lineWidth = 0.8
            path.stroke()
            ("NULL" as NSString).draw(at: NSPoint(x: pill.minX + 5, y: pill.minY + 1.5), withAttributes: attrs)
        } else if let text {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: GridColors.font,
                .foregroundColor: numeric ? GridColors.numeric : GridColors.text,
                .paragraphStyle: numeric ? Self.paragraphRight : Self.paragraphLeft,
                .strikethroughStyle: deleted ? NSUnderlineStyle.single.rawValue : 0,
                .strikethroughColor: GridColors.danger,
            ]
            (text as NSString).draw(with: NSRect(x: 8, y: (b.height - 16) / 2, width: b.width - 16, height: 17),
                                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        }
        if selectedCell {
            let path = NSBezierPath(roundedRect: b.insetBy(dx: 1.5, dy: 1.5), xRadius: 4, yRadius: 4)
            accent.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }
}

// MARK: - Header

final class GridHeaderView: NSTableHeaderView {
    override func draw(_ dirtyRect: NSRect) {
        GridColors.header.setFill()
        dirtyRect.fill()
        super.draw(dirtyRect)
        GridColors.line.setFill()
        NSRect(x: dirtyRect.minX, y: bounds.maxY - 1, width: dirtyRect.width, height: 1).fill()
    }
}

final class NativeHeaderCell: NSTableHeaderCell {
    // NSCell copies itself byte by byte, so Swift stored properties would be released twice.
    // Keep the data in NSCell's own properties, which it copies correctly.
    var typeName: String {
        get { representedObject as? String ?? "" }
        set { representedObject = newValue }
    }

    var sortAscending: Bool? {
        get { tag == 0 ? nil : tag == 1 }
        set { tag = newValue == nil ? 0 : (newValue! ? 1 : 2) }
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        GridColors.header.setFill()
        cellFrame.fill()
        GridColors.line.setFill()
        NSRect(x: cellFrame.maxX - 1, y: cellFrame.minY + 6, width: 1, height: cellFrame.height - 12).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        let left = NSMutableParagraphStyle()
        left.lineBreakMode = .byTruncatingTail
        left.alignment = alignment == .right ? .right : .left
        let indicator: CGFloat = sortAscending == nil ? 0 : 14
        let textRect = NSRect(x: cellFrame.minX + 8, y: cellFrame.minY + (typeName.isEmpty ? 9 : 3), width: cellFrame.width - 16 - indicator, height: 16)
        (stringValue as NSString).draw(with: textRect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [
            .font: Skin.current.gridHeaderFont
                ?? (Skin.current.isMatrix ? NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold) : NSFont.systemFont(ofSize: 12, weight: .semibold)),
            .foregroundColor: stringValue == "#" ? GridColors.tertiary : GridColors.text,
            .paragraphStyle: left,
        ])
        if !typeName.isEmpty {
            (typeName.lowercased() as NSString).draw(
                with: NSRect(x: cellFrame.minX + 8, y: cellFrame.minY + 18, width: cellFrame.width - 16 - indicator, height: 13),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: [.font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .medium), .foregroundColor: GridColors.tertiary, .paragraphStyle: left]
            )
        }
        if let ascending = sortAscending {
            let arrow = ascending ? "↑" : "↓"
            (arrow as NSString).draw(at: NSPoint(x: cellFrame.maxX - 18, y: cellFrame.minY + 9), withAttributes: [
                .font: NSFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: NSColor(Palette.current.accent),
            ])
        }
    }
}
