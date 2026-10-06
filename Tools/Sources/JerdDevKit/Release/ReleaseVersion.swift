/// A numeric version such as `0.1.0` or `14.0`. Missing parts count as zero, so `1.0` equals `1.0.0`.
struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// The text as written, for files and messages.
    let text: String
    /// The numeric parts, padded with zeros to four parts for comparison.
    let parts: [Int]

    /// Parses `count` dot-separated parts of decimal digits.
    init?(_ text: String, parts count: ClosedRange<Int> = 1...4) {
        let pieces = text.split(separator: ".", omittingEmptySubsequences: false)
        guard count.contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 9, piece.utf8.allSatisfy({ (48...57).contains($0) }),
                let number = Int(piece)
            else { return nil }
            numbers.append(number)
        }
        self.text = text
        parts = numbers + Array(repeating: 0, count: 4 - numbers.count)
    }

    var description: String { text }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.parts == rhs.parts }

    func hash(into hasher: inout Hasher) { hasher.combine(parts) }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.parts.lexicographicallyPrecedes(rhs.parts) }

    /// A release version: two to four parts, for example `0.1.0`.
    static func release(_ text: String) -> ReleaseVersion? { ReleaseVersion(text, parts: 2...4) }

    /// A build number: a positive decimal integer without a leading zero.
    static func build(_ text: String) -> Int? {
        guard let first = text.utf8.first, first != 48, text.count <= 9,
            text.utf8.allSatisfy({ (48...57).contains($0) })
        else { return nil }
        return Int(text)
    }
}
