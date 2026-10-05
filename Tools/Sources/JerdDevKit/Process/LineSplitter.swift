import Foundation

/// Splits a byte stream into complete text lines. A partial last line waits for more bytes or for `finish()`.
struct LineSplitter: Equatable {
    private var pending = Data()

    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            let lineBytes = pending[pending.startIndex..<newline]
            lines.append(String(decoding: lineBytes, as: UTF8.self))
            pending = Data(pending[pending.index(after: newline)...])
        }
        return lines
    }

    mutating func finish() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending = Data() }
        return String(decoding: pending, as: UTF8.self)
    }
}
