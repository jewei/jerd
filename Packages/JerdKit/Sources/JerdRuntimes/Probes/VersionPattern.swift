import Foundation
import JerdFoundation

/// How a version probe reads the version from command output. Pure.
package enum VersionPattern: Sendable, Equatable {
    /// The expected version, not inside a longer number: `(?<![0-9])<version>(?![0-9.])`.
    case bounded
    /// `cloudflared version <version>` at the start of the output, then white space or the end.
    case cloudflared
    /// The first word is `v<version>` (Caddy).
    case caddy
    /// `PHP <version> (<sapi>)` at the start of the output, for example `(cli)` or `(fpm-fcgi)`.
    case php(sapi: String)
    /// `PostgreSQL) <major.minor>`: the engine version, which differs from the Postgres.app version.
    case postgresEngine
    /// `Redis server v=<x.y.z>`, which must equal the expected version.
    case redis

    /// The version that the output proves, or nil when it does not match.
    package func version(in output: String, expected: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: expected)
        switch self {
        case .bounded: return Self.first(#"(?<![0-9])"# + escaped + #"(?![0-9.])"#, in: output).map { _ in expected }
        case .cloudflared:
            return Self.first("^cloudflared version " + escaped + #"(?=\s|$)"#, in: output).map { _ in expected }
        case .caddy:
            let word = output.split(whereSeparator: \.isWhitespace).first
            return word == Substring("v\(expected)") ? expected : nil
        case .php(let sapi):
            let pattern = "^PHP " + escaped + " \\(" + NSRegularExpression.escapedPattern(for: sapi) + "\\)"
            return Self.first(pattern, in: output).map { _ in expected }
        case .postgresEngine: return Self.first(#"PostgreSQL\) ([0-9]+\.[0-9]+(?:\.[0-9]+)?)"#, in: output, group: 1)
        case .redis:
            let found = Self.first(#"Redis server v=([0-9]+\.[0-9]+\.[0-9]+)"#, in: output, group: 1)
            return found == expected ? found : nil
        }
    }

    /// The error when the output does not match.
    package func mismatch(title: String) -> JerdError {
        switch self {
        case .php: .invalid("The downloaded PHP version does not match the release.")
        case .caddy: .invalid("The Caddy version does not match the release.")
        case .redis: .invalid("The runtime version does not match the release.")
        default: .invalid("The installed \(title) did not report the expected version.")
        }
    }

    private static func first(_ pattern: String, in text: String, group: Int = 0) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), let found = Range(match.range(at: group), in: text)
        else { return nil }
        return String(text[found])
    }
}
