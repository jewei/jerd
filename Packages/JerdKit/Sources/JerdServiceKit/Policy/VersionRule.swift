import Foundation

/// A pure rule that decides if the version output of a runtime binary names the registered version.
///
/// A version never matches inside a longer version: `8.4.1` does not match `8.4.11` or `18.4.1`.
public enum VersionRule: Equatable, Sendable {
    /// The version appears anywhere as a whole token, for example `mysqld  Ver 8.4.11 for macos15`.
    case standalone(version: String)
    /// A line starts with `label`, white space, an optional `v`, and the version. Mailpit prints
    /// its own path as the label, so a version that is only part of the path cannot match.
    case labelledLine(label: String, version: String)
    /// The first line starts with `label`, white space, an optional `v`, and the version, for
    /// example `rustfs 1.0.0`.
    case firstLine(label: String, version: String)

    /// True when `output` satisfies the rule.
    public func matches(_ output: String) -> Bool {
        switch self {
        case .standalone(let version):
            return Self.contains(output, pattern: "(?<![0-9.])\(Self.escape(version))(?![0-9.])")
        case .labelledLine(let label, let version):
            return Self.contains(output, pattern: "(?m)^\(Self.escape(label))\\s+v?\(Self.escape(version))(?![0-9.])")
        case .firstLine(let label, let version):
            let first = String(output.split(separator: "\n", omittingEmptySubsequences: false).first ?? "")
            return Self.contains(first, pattern: "^\(Self.escape(label))\\s+v?\(Self.escape(version))(?![0-9.])")
        }
    }

    private static func escape(_ text: String) -> String {
        NSRegularExpression.escapedPattern(for: text)
    }

    private static func contains(_ text: String, pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
