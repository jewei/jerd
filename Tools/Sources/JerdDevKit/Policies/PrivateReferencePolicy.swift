/// Code and documents state each rule themselves. They never cite the private design specs, review
/// files, work packages, or item lists of the rewrite, because no reader of the repository can open
/// them. A bare item number in parentheses also reads as a GitHub issue or pull request of this
/// repository, which it is not; a real GitHub reference uses its full URL.
enum PrivateReferencePolicy {
    /// The folders whose Swift sources and tests the policy reads, in addition to the Markdown files.
    static let swiftFolders = [
        "Packages/JerdKit/Sources", "Packages/JerdKit/Tests", "Apps", "Tools/Sources", "Tools/Tests",
    ]

    /// A spec section: "spec", a letter from A to G, and a number. A review ID: "review", a name,
    /// "-r", and the round number. A work package: "WP" and a number. An item: "(", "#", a number, and ")", or a
    /// comma-separated list of such numbers in one pair of parentheses.
    /// A computed list, because `Regex` is not `Sendable`.
    private static var patterns: [(pattern: Regex<Substring>, name: String)] {
        [
            (#/\b[Ss]pec [A-G] [0-9]/#, "a private spec"),
            (#/\b[Rr]eview [a-z]+(?:-[a-z]+)*-r[0-9]/#, "a private review"),
            (#/\bWP[0-9]+\b/#, "a private work package"),
            (#/\(#[0-9]+(?:, ?#[0-9]+)*\)/#, "a private item number"),
        ]
    }

    /// - Parameter files: Paths relative to the root, with their text.
    static func findings(files: [(path: String, text: String)]) -> [PolicyFinding] {
        let patterns = Self.patterns
        return files.flatMap { file in
            file.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated().compactMap {
                index, line -> PolicyFinding? in
                // A plain search first: `Regex` is slow, and almost no line has these words.
                guard line.contains("pec ") || line.contains("eview ") || line.contains("WP") || line.contains("(#"),
                    let match = patterns.first(where: { line.firstMatch(of: $0.pattern) != nil })
                else {
                    return nil
                }
                return PolicyFinding(
                    file: "\(file.path):\(index + 1)",
                    message: "Do not cite \(match.name). State the rule, or link to the document that states it.")
            }
        }
    }
}
