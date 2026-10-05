import Foundation

/// A dotted version such as `27.0` or `2.46.0`, parsed from tool output and pin files.
struct ToolVersion: Equatable, Comparable, CustomStringConvertible, Sendable {
    let components: [Int]

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Int($0) }
        guard !parts.isEmpty, numbers.count == parts.count else { return nil }
        components = numbers
    }

    var major: Int { components[0] }

    var description: String { components.map(String.init).joined(separator: ".") }

    /// `27`, `27.0`, and `27.0.0` are the same version.
    static func == (lhs: ToolVersion, rhs: ToolVersion) -> Bool {
        lhs.padded(to: rhs.components.count) == rhs.padded(to: lhs.components.count)
    }

    static func < (lhs: ToolVersion, rhs: ToolVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        return lhs.padded(to: count).lexicographicallyPrecedes(rhs.padded(to: count))
    }

    private func padded(to count: Int) -> [Int] {
        components + Array(repeating: 0, count: max(0, count - components.count))
    }

    /// The version after `marker` in tool output, for example "Xcode 27.0" or "Apple Swift version 6.4".
    static func parse(after marker: String, in output: String) -> ToolVersion? {
        guard let range = output.range(of: marker) else { return nil }
        let rest = output[range.upperBound...].drop { $0 == " " }
        let word = rest.prefix { $0.isNumber || $0 == "." }
        return ToolVersion(String(word))
    }
}
