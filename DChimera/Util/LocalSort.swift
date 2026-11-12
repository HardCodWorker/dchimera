import Foundation

/// Header sorting for grids whose rows are already loaded: query results and the Structure view.
/// The table tab sorts on the server instead (ORDER BY in the page query, see TableDataModel.toggleSort).
enum LocalSort {
    /// A header click cycles ascending → descending → off, like the table tab.
    static func next(_ sort: SortSpec?, _ column: String) -> SortSpec? {
        guard let sort, sort.column == column else { return SortSpec(column: column, ascending: true) }
        return sort.ascending ? SortSpec(column: column, ascending: false) : nil
    }

    /// Numbers compare as numbers when every value of the column is a number; text compares like Finder
    /// ("item 2" before "item 10"); NULL goes last in both directions. The sort is stable.
    static func sorted(_ rows: [[String?]], columns: [String], by sort: SortSpec?) -> [[String?]] {
        guard let sort, let c = columns.firstIndex(of: sort.column) else { return rows }
        func value(_ row: [String?]) -> String? { c < row.count ? row[c] : nil }
        func number(_ s: String) -> Double? {
            guard let d = Double(s.trimmingCharacters(in: .whitespaces)), d.isFinite else { return nil }
            return d
        }
        let numeric = rows.allSatisfy { value($0).map { number($0) != nil } ?? true }
        return rows.enumerated().sorted { a, b in
            switch (value(a.element), value(b.element)) {
            case (nil, nil): return a.offset < b.offset
            case (nil, _): return false
            case (_, nil): return true
            case let (x?, y?):
                let order: ComparisonResult
                if numeric, let dx = number(x), let dy = number(y) {
                    order = dx < dy ? .orderedAscending : dx > dy ? .orderedDescending : .orderedSame
                } else {
                    order = x.localizedStandardCompare(y)
                }
                if order == .orderedSame { return a.offset < b.offset }
                return sort.ascending ? order == .orderedAscending : order == .orderedDescending
            }
        }.map(\.element)
    }
}
