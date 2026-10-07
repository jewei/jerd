import Foundation

/// Reads and promotes release notes in `CHANGELOG.md`.
///
/// `./dev release` reads the `## [Unreleased]` notes before the build. Its release commit turns them
/// into a `## [V] - YYYY-MM-DD` section, so the feed, the GitHub release, and the changelog have the
/// same text.
enum ReleaseNotes {
    static let unreleasedHeading = "## [Unreleased]"

    /// The trimmed notes of the `## [version] - date` section, with one final line break.
    static func section(for version: String, in changelog: String) throws -> String {
        let lines = changelog.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { isHeading($0, of: version) }) else {
            throw DevFailure.checkFailed("CHANGELOG.md has no \"## [\(version)] - YYYY-MM-DD\" section.")
        }
        let body = body(after: start, in: lines)
        guard !body.isEmpty else {
            throw DevFailure.checkFailed("The CHANGELOG.md section of \(version) has no notes.")
        }
        return body + "\n"
    }

    /// The trimmed `## [Unreleased]` notes, or nil when the section is missing.
    static func unreleased(in changelog: String) -> String? {
        let lines = changelog.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(of: unreleasedHeading) else { return nil }
        return body(after: start, in: lines)
    }

    /// Moves the unreleased notes under a new `## [version] - date` heading and keeps an empty
    /// `## [Unreleased]` section above it.
    static func promoted(_ changelog: String, version: String, date: String) throws -> String {
        guard let notes = unreleased(in: changelog), !notes.isEmpty else {
            throw DevFailure.checkFailed("Add release notes to CHANGELOG.md under ## [Unreleased].")
        }
        if let line = notes.split(separator: "\n").first(where: { !isPlainTextItem($0) }) {
            throw DevFailure.checkFailed(
                "Sparkle shows the release notes as plain text. Write each note in CHANGELOG.md as one "
                    + "\"- \" list item without headings, links, or code marks: \(line)")
        }
        let lines = changelog.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.contains(where: { $0.hasPrefix("## [\(version)]") }) else {
            throw DevFailure.checkFailed("CHANGELOG.md already has a section for \(version).")
        }
        guard let index = lines.firstIndex(of: unreleasedHeading) else { preconditionFailure("checked above") }
        var result = lines
        result.replaceSubrange(index...index, with: [unreleasedHeading, "", "## [\(version)] - \(date)"])
        return result.joined(separator: "\n")
    }

    /// The unreleased notes of the next release, with one final line break. They must be plain-text
    /// items, and the changelog must have no section of `version` yet, so the release commit can promote them.
    static func forRelease(_ changelog: String, version: String) throws -> String {
        _ = try promoted(changelog, version: version, date: "2000-01-01")
        guard let notes = unreleased(in: changelog) else { preconditionFailure("checked by promoted") }
        return notes + "\n"
    }

    /// The text of `release-notes.md`: the notes and the system requirement.
    static func file(notes: String, minimumMacOS: ReleaseVersion) -> String {
        notes + "\nRequires Apple Silicon and macOS \(minimumMacOS) or later.\n"
    }

    /// `YYYY-MM-DD` in UTC.
    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    /// A note line that reads well as plain text: a `- ` item or its indented continuation, with no
    /// Markdown link or code mark.
    static func isPlainTextItem(_ line: Substring) -> Bool {
        (line.hasPrefix("- ") || line.hasPrefix("  ")) && !line.contains("`") && !line.contains("](")
    }

    static func isHeading(_ line: String, of version: String) -> Bool {
        let prefix = "## [\(version)] - "
        guard line.hasPrefix(prefix) else { return false }
        let date = line.dropFirst(prefix.count)
        let shape = date.map { $0 == "-" ? "-" : ($0.isASCII && $0.isNumber ? "9" : "?") }.joined()
        return shape == "9999-99-99"
    }

    private static func body(after heading: Int, in lines: [String]) -> String {
        let rest = lines[(heading + 1)...]
        let end = rest.firstIndex { $0.hasPrefix("## [") } ?? lines.endIndex
        return lines[(heading + 1)..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
