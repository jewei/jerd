import Foundation

/// The CI cache of prepared runtimes is reused while its key stays the same, and a preparation that
/// finds a payload folder keeps it. So the key must hash every input that changes the prepared bytes:
/// the catalog, the deployment target, and the preparation code. Otherwise CI tests stale payloads.
/// The policy also refuses a key pattern whose fixed part names no file, because a renamed folder
/// would silently drop out of the key.
enum RuntimeCacheKeyPolicy {
    static let file = ".github/workflows/ci.yml"
    static let keyPrefix = "key: runtimes-"

    /// The `hashFiles` patterns that the runtime cache key must contain.
    static let requiredInputs = [
        "Runtimes/**",
        "Configuration/Base.xcconfig",
        "Packages/JerdKit/Sources/JerdManifest/**",
        "Packages/JerdKit/Sources/JerdRuntimes/Preparation/**",
        "Packages/JerdKit/Sources/JerdRuntimes/Installation/**",
        "Packages/JerdKit/Sources/JerdRuntimes/Payloads/**",
        "Packages/JerdKit/Sources/JerdRuntimes/Releases/**",
        "Packages/JerdKit/Sources/JerdRuntimes/Bundled/PinnedPayloadPreparer.swift",
        "Packages/JerdKit/Sources/JerdRuntimes/Bundled/RuntimePin+Release.swift",
        "Tools/Sources/JerdDevKit/Runtimes/**",
    ]

    /// - Parameters:
    ///   - workflow: The text of the CI workflow.
    ///   - pathExists: Tells whether a repository-relative file or folder exists.
    static func findings(workflow: String, pathExists: (String) -> Bool) -> [PolicyFinding] {
        guard let patterns = keyPatterns(in: workflow) else {
            return [PolicyFinding(file: file, message: "The runtime cache key with hashFiles(…) is missing.")]
        }
        var findings: [PolicyFinding] = []
        for input in requiredInputs where !patterns.contains(input) {
            findings.append(PolicyFinding(file: file, message: "The runtime cache key does not hash \(input)."))
        }
        for pattern in patterns where !pathExists(fixedPart(of: pattern)) {
            findings.append(
                PolicyFinding(file: file, message: "The runtime cache key pattern \(pattern) names no file."))
        }
        return findings
    }

    /// The quoted `hashFiles` arguments of the one `key: runtimes-…` line, or nil without such a line.
    static func keyPatterns(in workflow: String) -> [String]? {
        let line = workflow.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix(keyPrefix) }
        guard let line, let start = line.range(of: "hashFiles(") else { return nil }
        let arguments = line[start.upperBound...].prefix { $0 != ")" }
        let parts = arguments.split(separator: "'", omittingEmptySubsequences: false)
        // The quoted values are at the odd positions between single quotes.
        let patterns = parts.indices.filter { $0 % 2 == 1 }.map { String(parts[$0]) }
        return patterns.isEmpty ? nil : patterns
    }

    /// The path before the first glob character, without a trailing slash.
    static func fixedPart(of pattern: String) -> String {
        let fixed = pattern.prefix { !"*?[".contains($0) }
        return fixed.hasSuffix("/") ? String(fixed.dropLast()) : String(fixed)
    }
}
