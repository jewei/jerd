import Foundation

/// Relative links in the Markdown documents must point to files that exist. Web links are not checked:
/// the check must work without a network.
enum MarkdownLinkPolicy {
    // `Regex` is not `Sendable`, so each use makes a new value instead of sharing a static one.

    /// Inline links and images: `[text](target)`, `[text](<target>)`, and `[text](target "title")`.
    private static var inlineLink: Regex<(Substring, Substring?, Substring?)> {
        #/\]\(\s*(?:<([^>]+)>|([^)\s]+))/#
    }

    /// Reference definitions: `[label]: target`.
    private static var referenceDefinition: Regex<(Substring, Substring?, Substring?)> {
        #/^\s{0,3}\[[^\]]+\]:\s*(?:<([^>]+)>|(\S+))/#
    }

    private static var codeSpan: Regex<Substring> { #/`+[^`]*`+/# }

    static func findings(file: String, markdown: String, exists: (String) -> Bool) -> [PolicyFinding] {
        localTargets(in: markdown).compactMap { target in
            guard let path = resolve(target, from: file) else {
                return PolicyFinding(file: file, message: "The link \(target) points outside the repository.")
            }
            return exists(path)
                ? nil : PolicyFinding(file: file, message: "The link \(target) points to a missing file.")
        }
    }

    /// Link targets outside code, without web links and without page anchors.
    static func localTargets(in markdown: String) -> [String] {
        var targets: [String] = []
        var inFence = false
        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = rawLine.drop { $0 == " " }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }
            let line = String(rawLine).replacing(codeSpan, with: "")
            var found = line.matches(of: inlineLink).map { String($0.output.1 ?? $0.output.2 ?? "") }
            if let definition = line.firstMatch(of: referenceDefinition) {
                found.append(String(definition.output.1 ?? definition.output.2 ?? ""))
            }
            targets += found.filter(isLocal)
        }
        return targets
    }

    static func isLocal(_ target: String) -> Bool {
        !target.isEmpty && !target.hasPrefix("#") && !target.contains("://") && !target.hasPrefix("mailto:")
    }

    /// The repository-relative path of a link target, or `nil` when the target leaves the repository.
    /// A target that starts with `/` is relative to the repository root, as on GitHub.
    static func resolve(_ target: String, from file: String) -> String? {
        let withoutAnchor = target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let withoutQuery = withoutAnchor.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let decoded = String(withoutQuery).removingPercentEncoding ?? String(withoutQuery)
        var components: [Substring] = decoded.hasPrefix("/") ? [] : file.split(separator: "/").dropLast()
        for part in decoded.split(separator: "/") {
            switch part {
            case ".":
                continue
            case "..":
                guard !components.isEmpty else { return nil }
                components.removeLast()
            default:
                components.append(part)
            }
        }
        return components.isEmpty ? "." : components.joined(separator: "/")
    }
}
