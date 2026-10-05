import Foundation

/// The app update feed URL and public key. Installed copies of Jerd trust only this feed and key, so a
/// change needs a migration plan (AGENTS.md, Compatibility contract). The two values have one home:
/// one unconditional assignment each in `Configuration/App.xcconfig`. Any other assignment could
/// change the effective value for one configuration, SDK, or architecture, so the policy refuses:
/// - a conditional assignment such as `JERD_UPDATE_FEED_URL[config=Release] = …`, in any xcconfig;
/// - an assignment in another xcconfig, or a second assignment in `App.xcconfig`;
/// - any mention of the two names, `SUFeedURL`, or `SUPublicEDKey` in `project.yml`, whose target
///   settings override the xcconfig, and the two Info.plist keys in any xcconfig;
/// - an `#include` of a file outside `Configuration/`, which the policy cannot see.
/// `BuiltAppPolicy` then checks the effective values in the built Info.plist.
enum UpdateSettingsPolicy {
    static let file = "Configuration/App.xcconfig"
    static let projectSpec = "project.yml"
    static let feedURL = "https://raw.githubusercontent.com/jewei/jerd/main/appcast.xml"
    static let publicKey = "FjYzr89ynpNrTtI8Me8zqA88YYJrRmloo4bj6dLbAJA="
    static let settingNames = ["JERD_UPDATE_FEED_URL", "JERD_UPDATE_PUBLIC_KEY"]
    static let infoPlistKeys = ["SUFeedURL", "SUPublicEDKey"]

    /// One `NAME = value` or `NAME[condition] = value` line.
    struct Assignment: Equatable {
        var name: String
        var isConditional: Bool
        var value: String
    }

    /// - Parameters:
    ///   - xcconfigs: Every `Configuration/*.xcconfig`, with its repository-relative path and text.
    ///   - projectSpec: The text of `project.yml`.
    static func findings(xcconfigs: [(path: String, text: String)], projectSpec: String) -> [PolicyFinding] {
        var findings: [PolicyFinding] = []
        for (path, text) in xcconfigs {
            findings += placementFindings(path: path, text: text)
        }
        let appText = xcconfigs.first { $0.path == file }?.text ?? ""
        findings += valueFindings(assignments(in: appText))
        for name in settingNames + infoPlistKeys where projectSpec.contains(name) {
            findings.append(
                PolicyFinding(file: Self.projectSpec, message: "\(name) must not appear here; set it only in \(file)."))
        }
        return findings
    }

    /// Assignments outside their one home, Info.plist keys in build settings, and outside includes.
    static func placementFindings(path: String, text: String) -> [PolicyFinding] {
        var findings: [PolicyFinding] = []
        for assignment in assignments(in: text) where settingNames.contains(assignment.name) {
            if assignment.isConditional {
                findings.append(
                    PolicyFinding(
                        file: path,
                        message:
                            "\(assignment.name) has a conditional assignment; only one plain assignment is allowed."))
            } else if path != file {
                findings.append(PolicyFinding(file: path, message: "\(assignment.name) must be set only in \(file)."))
            }
        }
        for key in infoPlistKeys where text.contains(key) {
            findings.append(PolicyFinding(file: path, message: "\(key) must come only from Info.plist and \(file)."))
        }
        for include in includes(in: text) where include.contains("/") {
            findings.append(PolicyFinding(file: path, message: "#include \"\(include)\" leaves Configuration/."))
        }
        return findings
    }

    /// The pinned values, each set exactly once without a condition in `App.xcconfig`.
    static func valueFindings(_ assignments: [Assignment]) -> [PolicyFinding] {
        let plain = assignments.filter { !$0.isConditional }
        var findings: [PolicyFinding] = []
        for name in settingNames {
            let values = plain.filter { $0.name == name }.map(\.value)
            guard let value = values.first else {
                findings.append(PolicyFinding(file: file, message: "\(name) is missing."))
                continue
            }
            if values.count > 1 {
                findings.append(
                    PolicyFinding(file: file, message: "\(name) is set \(values.count) times; set it once."))
            }
            if let problem = valueProblem(name: name, value: value) {
                findings.append(PolicyFinding(file: file, message: problem))
            }
        }
        return findings
    }

    static func valueProblem(name: String, value: String) -> String? {
        switch name {
        case "JERD_UPDATE_FEED_URL" where value != feedURL:
            return "\(name) is \(value); installed apps use \(feedURL)."
        case "JERD_UPDATE_PUBLIC_KEY" where Data(base64Encoded: value)?.count != 32:
            return "\(name) is not a base64 Ed25519 public key."
        case "JERD_UPDATE_PUBLIC_KEY" where value != publicKey:
            return "\(name) is not the key that installed apps trust."
        default:
            return nil
        }
    }

    /// Reads every assignment. It removes `//` comments and the empty `$()` that xcconfig files use to
    /// write `//` inside a value.
    static func assignments(in text: String) -> [Assignment] {
        text.split(separator: "\n").compactMap { rawLine in
            let line = rawLine.range(of: "//").map { rawLine[..<$0.lowerBound] } ?? rawLine
            // A condition such as `[config=Release]` has its own `=`, so the assignment starts after it.
            let conditionEnd = line.firstIndex(of: "[").flatMap { _ in line.firstIndex(of: "]") }
            let searchStart = conditionEnd.map { line.index(after: $0) } ?? line.startIndex
            guard let equals = line[searchStart...].firstIndex(of: "=") else { return nil }
            let left = line[..<equals].trimmingCharacters(in: .whitespaces)
            let name = left.prefix { $0 != "[" }.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.contains(" "), !name.hasPrefix("#") else { return nil }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            return Assignment(
                name: name, isConditional: left.contains("["), value: value.replacingOccurrences(of: "$()", with: ""))
        }
    }

    /// The file names of `#include` and `#include?` lines.
    static func includes(in text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#include") else { return nil }
            let parts = trimmed.split(separator: "\"")
            return parts.count >= 2 ? String(parts[1]) : nil
        }
    }
}
