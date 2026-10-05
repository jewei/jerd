/// A stable numeric release version with two to four parts, for example `8.5.11`.
///
/// Rules: one leading `v` is removed; 2–4 parts; each part has only ASCII digits and is
/// below 100 000. Pre-release forms such as `8.6.0RC1` or `8.6.0-beta` are refused.
/// Missing parts are zero, so `v8.5.11` equals `8.5.11.0`.
public struct RuntimeVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    /// Always four numbers.
    public let components: [Int]

    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? text.dropFirst() : Substring(text)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...4).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                let number = Int(part), number < 100_000
            else { return nil }
            numbers.append(number)
        }
        components = numbers + Array(repeating: 0, count: 4 - numbers.count)
    }

    /// The first `count` numbers joined with dots, for example `8.5` for the PHP branch.
    public func prefix(_ count: Int) -> String {
        components.prefix(count).map(String.init).joined(separator: ".")
    }

    public var description: String { components.map(String.init).joined(separator: ".") }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}
