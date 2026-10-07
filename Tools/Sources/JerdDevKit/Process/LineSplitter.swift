import Foundation

/// Splits a byte stream into complete text lines. A partial last line waits for more bytes or for `finish()`.
/// Each byte is scanned once and the buffer is compacted once for each `append`, so the cost is linear.
struct LineSplitter: Equatable {
    private var pending = Data()
    /// The number of pending bytes that are known to have no line break.
    private var scanned = 0

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        var lineStart = pending.startIndex
        var searchStart = pending.startIndex + scanned
        while let newline = pending[searchStart...].firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(String(decoding: pending[lineStart..<newline], as: UTF8.self))
            lineStart = newline + 1
            searchStart = lineStart
        }
        if lineStart != pending.startIndex {
            pending = Data(pending[lineStart...])
        }
        scanned = pending.count
        return lines
    }

    mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        defer {
            pending = Data()
            scanned = 0
        }
        return String(decoding: pending, as: UTF8.self)
    }
}
