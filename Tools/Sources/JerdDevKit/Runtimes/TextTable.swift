import Foundation

/// Renders rows as left-aligned columns separated by two spaces. The last column is not padded.
enum TextTable {
    static func render(_ rows: [[String]]) -> String {
        let columnCount = rows.map(\.count).max() ?? 0
        let widths = (0..<columnCount).map { column in
            rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0
        }
        return rows.map { row in
            row.enumerated().map { column, text in
                column == row.count - 1 ? text : text.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }.joined(separator: "\n")
    }
}
