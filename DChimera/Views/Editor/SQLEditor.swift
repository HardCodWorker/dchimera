import AppKit
import SwiftUI

extension NSColor {
    var asColor: Color { Color(nsColor: self) }
}

// MARK: - Syntax colors

enum SyntaxColors {
    static func dynamic(_ light: UInt32, _ dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        }
    }

    static var keyword: NSColor { Skin.current.keyword.ns }
    static var string: NSColor { Skin.current.string.ns }
    static var number: NSColor { Skin.current.number.ns }
    static var comment: NSColor { Skin.current.comment.ns }
    static var quoted: NSColor { Skin.current.quoted.ns }
    static var function: NSColor { Skin.current.function.ns }
    static var param: NSColor { Skin.current.param.ns }
    static var text: NSColor { Skin.current.nsText }
    static var caret: NSColor { NSColor(Palette.current.accent) }

    static func color(_ kind: SQLText.TokenKind) -> NSColor? {
        switch kind {
        case .keyword: keyword
        case .string: string
        case .number: number
        case .comment: comment
        case .quotedIdent: quoted
        case .function: function
        case .param: param
        case .identifier, .punct: nil
        }
    }

    /// SwiftUI rendering of SQL; `onAccent` uses light colors for text on the accent bubble.
    static func attributed(_ sql: String, onAccent: Bool, size: CGFloat = 12.5) -> AttributedString {
        var out = AttributedString(sql)
        out.font = .system(size: size, design: .monospaced)
        out.foregroundColor = onAccent ? .white : Theme.text
        let ns = sql as NSString
        for token in SQLText.tokenize(ns) {
            guard let range = Range(token.range, in: sql), let r = Range(range, in: out) else { continue }
            if onAccent {
                switch token.kind {
                case .keyword: out[r].font = .system(size: size, weight: .bold, design: .monospaced)
                case .string: out[r].foregroundColor = Color(hex: 0xFFF1B8)
                case .number: out[r].foregroundColor = Color(hex: 0xFFD6C2)
                case .comment: out[r].foregroundColor = .white.opacity(0.6)
                case .quotedIdent: out[r].foregroundColor = Color(hex: 0xD6F4FF)
                case .function: out[r].foregroundColor = Color(hex: 0xD9F2FF)
                case .param: out[r].foregroundColor = Color(hex: 0xFFE08A)
                default: break
                }
            } else if let c = color(token.kind) {
                out[r].foregroundColor = Color(nsColor: c)
                if token.kind == .keyword { out[r].font = .system(size: size, weight: .semibold, design: .monospaced) }
            }
        }
        return out
    }
}

// MARK: - Completion

struct CompletionItem: Identifiable, Equatable {
    enum Kind { case table, view, column, keyword, function }
    let id = UUID()
    var text: String
    var detail: String
    var kind: Kind

    var symbol: String {
        switch kind {
        case .table: "tablecells"
        case .view: "eye"
        case .column: "line.3.horizontal"
        case .keyword: "textformat"
        case .function: "function"
        }
    }

    static func == (a: CompletionItem, b: CompletionItem) -> Bool { a.text == b.text && a.kind == b.kind }
}

/// Bridges the NSTextView and SwiftUI: cursor-aware run, completion list, focus.
@MainActor
final class EditorController: ObservableObject {
    weak var textView: SQLTextView?
    @Published var items: [CompletionItem] = []
    @Published var selected = 0
    @Published var anchor: CGPoint = .zero
    var tables: () -> [TableRef] = { [] }
    var columns: () -> [ColumnBrief] = { [] }
    private var prefixRange = NSRange(location: 0, length: 0)

    var isShowingCompletions: Bool { !items.isEmpty }

    func focus() {
        guard let tv = textView else { return }
        tv.window?.makeFirstResponder(tv)
    }

    var text: String { textView?.string ?? "" }

    /// Selected text, or the statement under the cursor.
    func currentStatement() -> String? {
        guard let tv = textView else { return nil }
        let ns = tv.string as NSString
        let sel = tv.selectedRange()
        if sel.length > 0 { return ns.substring(with: sel) }
        guard let range = SQLText.statement(at: sel.location, in: ns) else { return nil }
        return ns.substring(with: range)
    }

    func setText(_ s: String) {
        guard let tv = textView else { return }
        tv.string = s
        tv.didChangeText()
        tv.setSelectedRange(NSRange(location: (s as NSString).length, length: 0))
        hide()
    }

    func insert(_ s: String) {
        guard let tv = textView else { return }
        tv.insertText(s, replacementRange: tv.selectedRange())
    }

    func hide() {
        if !items.isEmpty { withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { items = [] } }
    }

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selected = (selected + delta + items.count) % items.count
    }

    func accept(_ item: CompletionItem? = nil) {
        guard let tv = textView else { return }
        let chosen = item ?? (items.indices.contains(selected) ? items[selected] : nil)
        guard let chosen else { return }
        var insertion = chosen.text
        if chosen.kind == .function { insertion += "(" }
        if chosen.kind == .keyword { insertion += " " }
        tv.insertText(insertion, replacementRange: prefixRange)
        hide()
    }

    /// Recomputes suggestions after typing.
    func update() {
        guard let tv = textView else { return }
        let ns = tv.string as NSString
        let caret = tv.selectedRange().location
        guard tv.selectedRange().length == 0, caret <= ns.length else { hide(); return }

        var start = caret
        while start > 0 {
            let c = ns.character(at: start - 1)
            let isWord = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127
            if !isWord { break }
            start -= 1
        }
        let prefix = ns.substring(with: NSRange(location: start, length: caret - start))
        let afterDot = start > 0 && ns.character(at: start - 1) == 46

        // Do not suggest inside strings or comments.
        let tokens = SQLText.tokenize(ns)
        if tokens.contains(where: { ($0.kind == .string || $0.kind == .comment || $0.kind == .quotedIdent) && NSLocationInRange(max(caret - 1, 0), $0.range) && caret > $0.range.location }) {
            hide(); return
        }
        guard prefix.count >= 1 || afterDot else { hide(); return }
        prefixRange = NSRange(location: start, length: caret - start)

        let lower = prefix.lowercased()
        var candidates: [CompletionItem] = []
        let statementRange = SQLText.statement(at: caret, in: ns) ?? NSRange(location: 0, length: ns.length)
        let statement = ns.substring(with: statementRange)
        let aliases = Self.aliases(in: statement)
        let allColumns = columns()
        let allTables = tables()

        if afterDot {
            var q = start - 1
            var qs = q
            while qs > 0 {
                let c = ns.character(at: qs - 1)
                let isWord = (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c > 127
                if !isWord { break }
                qs -= 1
            }
            q = start - 1
            let qualifier = ns.substring(with: NSRange(location: qs, length: q - qs)).lowercased()
            let tableName = aliases[qualifier] ?? qualifier
            let cols = allColumns.filter { $0.table.lowercased() == tableName }
            candidates = cols.map { CompletionItem(text: $0.column, detail: $0.type, kind: .column) }
            if cols.isEmpty {
                // schema-qualified table names: schema.<table>
                candidates = allTables.filter { $0.schema.lowercased() == qualifier }.map {
                    CompletionItem(text: $0.name, detail: $0.kind == .table ? "table" : "view", kind: $0.kind == .table ? .table : .view)
                }
            }
        } else {
            let previousWord = Self.previousWord(ns, before: start).uppercased()
            let wantsTable = ["FROM", "JOIN", "UPDATE", "INTO", "TABLE", "DESCRIBE"].contains(previousWord)
            let tableItems = allTables.map { t -> CompletionItem in
                let defaultSchema = ["public", "main"].contains(t.schema) || allTables.allSatisfy { $0.schema == t.schema }
                return CompletionItem(text: defaultSchema ? t.name : "\(t.schema).\(t.name)",
                                      detail: t.estimatedRows.map { "\(Fmt.compact($0)) rows" } ?? (t.kind == .table ? "table" : "view"),
                                      kind: t.kind == .table ? .table : .view)
            }
            if wantsTable {
                candidates = tableItems
            } else {
                let mentioned = Set(aliases.values)
                let cols = allColumns.filter { mentioned.contains($0.table.lowercased()) }
                var seen = Set<String>()
                candidates = cols.compactMap { seen.insert($0.column).inserted ? CompletionItem(text: $0.column, detail: $0.type, kind: .column) : nil }
                candidates += tableItems
                candidates += SQLText.functions.map { CompletionItem(text: $0, detail: "function", kind: .function) }
                let isUpper = prefix.first.map { $0.isUppercase } ?? true
                candidates += SQLText.keywords.sorted().map { CompletionItem(text: isUpper ? $0 : $0.lowercased(), detail: "keyword", kind: .keyword) }
            }
        }

        let ranked: [CompletionItem]
        if lower.isEmpty {
            ranked = Array(candidates.prefix(8))
        } else {
            let starts = candidates.filter { $0.text.lowercased().hasPrefix(lower) && $0.text.lowercased() != lower }
            let contains = candidates.filter { !$0.text.lowercased().hasPrefix(lower) && $0.text.lowercased().contains(lower) }
            ranked = Array((starts + contains).prefix(8))
        }

        guard !ranked.isEmpty else { hide(); return }
        anchor = caretPoint(start)
        let changed = ranked != items
        if items.isEmpty {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) { items = ranked }
        } else if changed {
            items = ranked
        }
        if changed { selected = 0 }
    }

    /// Top-left of the word start, in the editor's visible coordinates (top-left origin).
    private func caretPoint(_ location: Int) -> CGPoint {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return .zero }
        let glyph = lm.glyphIndexForCharacter(at: min(location, max((tv.string as NSString).length - 1, 0)))
        var rect = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 0), in: tc)
        if (tv.string as NSString).length == 0 { rect = .zero }
        if location >= (tv.string as NSString).length, location > 0 {
            let lastGlyph = lm.glyphIndexForCharacter(at: location - 1)
            let r = lm.boundingRect(forGlyphRange: NSRange(location: lastGlyph, length: 1), in: tc)
            rect = CGRect(x: r.maxX, y: r.minY, width: 0, height: r.height)
        }
        let origin = tv.textContainerOrigin
        let visible = tv.visibleRect
        return CGPoint(x: rect.minX + origin.x - visible.minX, y: rect.minY + origin.y - visible.minY)
    }

    private static func previousWord(_ ns: NSString, before location: Int) -> String {
        var end = location
        while end > 0, let s = UnicodeScalar(ns.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(s) { end -= 1 }
        var start = end
        while start > 0 {
            let c = ns.character(at: start - 1)
            let isWord = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
            if !isWord { break }
            start -= 1
        }
        return ns.substring(with: NSRange(location: start, length: end - start))
    }

    /// alias → table name (both lowercased) for `FROM table alias` / `JOIN schema.table AS alias`.
    static func aliases(in statement: String) -> [String: String] {
        var map: [String: String] = [:]
        let pattern = #"(?i)\b(?:from|join|update|into)\s+(?:[`"]?\w+[`"]?\.)?[`"]?(\w+)[`"]?(?:\s+(?:as\s+)?(\w+))?"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return map }
        let ns = statement as NSString
        let reserved: Set<String> = ["where", "on", "join", "left", "right", "inner", "outer", "group", "order", "limit", "set", "values", "using", "cross", "full", "natural", "union", "select"]
        for m in re.matches(in: statement, range: NSRange(location: 0, length: ns.length)) {
            let table = ns.substring(with: m.range(at: 1)).lowercased()
            map[table] = table
            if m.range(at: 2).location != NSNotFound {
                let alias = ns.substring(with: m.range(at: 2)).lowercased()
                if !reserved.contains(alias) { map[alias] = table }
            }
        }
        return map
    }
}

// MARK: - NSTextView

final class SQLTextView: NSTextView {
    weak var controller: EditorController?
    var onHistoryUp: (() -> Void)?
    var onEscape: (() -> Void)?
    /// ⌘↩ runs the current statement, ⇧⌘↩ runs everything.
    var onRun: ((_ all: Bool) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 36 || event.keyCode == 76), flags.contains(.command), window?.firstResponder === self, let onRun {
            controller?.hide()
            onRun(flags.contains(.shift))
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let controller, controller.isShowingCompletions {
            switch event.keyCode {
            case 125: controller.move(1); return
            case 126: controller.move(-1); return
            case 36, 76, 48:
                if !event.modifierFlags.contains(.command) { controller.accept(); return }
            case 53: controller.hide(); return
            default: break
            }
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if (event.keyCode == 36 || event.keyCode == 76), flags.contains(.command), let onRun {
            controller?.hide()
            onRun(flags.contains(.shift))
            return
        }
        if event.keyCode == 126, string.isEmpty, let onHistoryUp {
            onHistoryUp()
            return
        }
        if event.keyCode == 53 {
            onEscape?()
        }
        if event.keyCode == 48, !event.modifierFlags.contains(.shift) {
            insertText("  ", replacementRange: selectedRange())
            return
        }
        super.keyDown(with: event)
    }

    override func resignFirstResponder() -> Bool {
        let r = super.resignFirstResponder()
        if r { Task { @MainActor in controller?.hide() } }
        return r
    }
}

struct SQLEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var contentHeight: CGFloat
    var controller: EditorController
    var fontSize: CGFloat = 13
    var onRun: ((_ all: Bool) -> Void)?
    var onHistoryUp: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder

        let tv = SQLTextView()
        tv.controller = controller
        tv.onHistoryUp = onHistoryUp
        tv.onRun = onRun
        tv.delegate = context.coordinator
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        tv.textColor = SyntaxColors.text
        tv.insertionPointColor = SyntaxColors.caret
        tv.textContainerInset = NSSize(width: 0, height: 2)
        tv.textContainer?.lineFragmentPadding = 0
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.minSize = NSSize(width: 0, height: 0)
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.string = text
        scroll.documentView = tv
        controller.textView = tv
        context.coordinator.highlight(tv)
        DispatchQueue.main.async { context.coordinator.reportHeight(tv) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let tv = scroll.documentView as? SQLTextView else { return }
        tv.onHistoryUp = onHistoryUp
        tv.onRun = onRun
        if tv.string != text {
            tv.string = text
            context.coordinator.highlight(tv)
            context.coordinator.reportHeight(tv)
        }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        if tv.font != font {
            tv.font = font
            context.coordinator.highlight(tv)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SQLEditor

        init(_ parent: SQLEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? SQLTextView else { return }
            parent.text = tv.string
            highlight(tv)
            reportHeight(tv)
            parent.controller.update()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView, parent.controller.isShowingCompletions else { return }
            // Moving the caret away from the word closes the list.
            if tv.selectedRange().length > 0 { parent.controller.hide() }
        }

        func highlight(_ tv: NSTextView) {
            guard let storage = tv.textStorage else { return }
            let ns = storage.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            let font = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .regular)
            let bold = NSFont.monospacedSystemFont(ofSize: parent.fontSize, weight: .semibold)
            storage.beginEditing()
            storage.setAttributes([.font: font, .foregroundColor: SyntaxColors.text], range: full)
            for token in SQLText.tokenize(ns) {
                guard let color = SyntaxColors.color(token.kind) else { continue }
                storage.addAttribute(.foregroundColor, value: color, range: token.range)
                if token.kind == .keyword { storage.addAttribute(.font, value: bold, range: token.range) }
            }
            storage.endEditing()
            tv.typingAttributes = [.font: font, .foregroundColor: SyntaxColors.text]
        }

        func reportHeight(_ tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let used = lm.usedRect(for: tc).height + tv.textContainerInset.height * 2
            let h = max(used, parent.fontSize + 8)
            if abs(parent.contentHeight - h) > 0.5 {
                DispatchQueue.main.async { self.parent.contentHeight = h }
            }
        }
    }
}

/// Floating list of suggestions shown above the caret.
struct CompletionPopup: View {
    @ObservedObject var controller: EditorController
    @Environment(\.palette) private var palette

    var body: some View {
        if !controller.items.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(controller.items.enumerated()), id: \.element.id) { i, item in
                    let isSelected = i == controller.selected
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(isSelected ? Theme.onAccent : iconColor(item.kind))
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? Theme.onAccent.opacity(0.22) : iconColor(item.kind).opacity(0.14)))
                        Text(item.text)
                            .font(Theme.mono(12.5, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 12)
                        Text(item.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(isSelected ? Theme.onAccent.opacity(0.8) : Theme.secondaryText)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .foregroundStyle(isSelected ? Theme.onAccent : .primary)
                    .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? AnyShapeStyle(palette.gradient) : AnyShapeStyle(Color.clear)))
                    .contentShape(Rectangle())
                    .onTapGesture { controller.accept(item) }
                }
            }
            .padding(4)
            .frame(width: 330)
            .skinPopup(radius: 12)
            .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
            .animation(.spring(response: 0.22, dampingFraction: 0.85), value: controller.selected)
        }
    }

    private func iconColor(_ kind: CompletionItem.Kind) -> Color {
        switch kind {
        case .table: palette.accent
        case .view: Color(hex: 0x14A982)
        case .column: Color(hex: 0xE58A1F)
        case .keyword: Color(hex: 0x8A3FD1)
        case .function: Color(hex: 0x1F68E0)
        }
    }
}
