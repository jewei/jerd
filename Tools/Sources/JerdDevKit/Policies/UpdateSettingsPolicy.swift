import Foundation

/// The app update feed URL and public key in `Configuration/App.xcconfig`. Installed copies of Jerd
/// trust only this feed and key, so a change needs a migration plan (AGENTS.md, Compatibility contract).
enum UpdateSettingsPolicy {
    static let file = "Configuration/App.xcconfig"
    static let feedURL = "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml"
    static let publicKey = "FjYzr89ynpNrTtI8Me8zqA88YYJrRmloo4bj6dLbAJA="

    static func findings(xcconfig: String) -> [PolicyFinding] {
        let settings = parseSettings(xcconfig)
        var findings: [PolicyFinding] = []
        switch settings["JERD_UPDATE_FEED_URL"] {
        case nil:
            findings.append(PolicyFinding(file: file, message: "JERD_UPDATE_FEED_URL is missing."))
        case let value? where value != feedURL:
            findings.append(
                PolicyFinding(file: file, message: "JERD_UPDATE_FEED_URL is \(value); installed apps use \(feedURL)."))
        default:
            break
        }
        switch settings["JERD_UPDATE_PUBLIC_KEY"] {
        case nil:
            findings.append(PolicyFinding(file: file, message: "JERD_UPDATE_PUBLIC_KEY is missing."))
        case let value? where Data(base64Encoded: value)?.count != 32:
            findings.append(
                PolicyFinding(file: file, message: "JERD_UPDATE_PUBLIC_KEY is not a base64 Ed25519 public key."))
        case let value? where value != publicKey:
            findings.append(
                PolicyFinding(file: file, message: "JERD_UPDATE_PUBLIC_KEY is not the key that installed apps trust."))
        default:
            break
        }
        return findings
    }

    /// Reads unconditional `NAME = value` lines. It removes `//` comments and the empty `$()` that
    /// xcconfig files use to write `//` inside a value.
    static func parseSettings(_ text: String) -> [String: String] {
        var settings: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.range(of: "//").map { rawLine[..<$0.lowerBound] } ?? rawLine
            guard let equals = line.firstIndex(of: "=") else { continue }
            let name = line[..<equals].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains("["), !name.contains(" ") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            settings[name] = value.replacingOccurrences(of: "$()", with: "")
        }
        return settings
    }
}
