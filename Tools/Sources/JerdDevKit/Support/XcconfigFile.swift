import Foundation

/// A parsed Xcode build settings file (`.xcconfig`) that keeps every line, so that a change of one
/// value leaves the rest of the file byte for byte as it was.
///
/// The release reads the app version from `Configuration/Version.xcconfig` and changes it only through
/// this type. A setting must have exactly one plain assignment: a second assignment or a conditional
/// form such as `NAME[config=Release]` would make the value depend on the build, so it is refused.
struct XcconfigFile: Equatable, Sendable {
    /// One `NAME = value` or `NAME[condition] = value` line. A trailing `//` comment is not part of the value.
    struct Assignment: Equatable, Sendable {
        var name: String
        var condition: String?
        var value: String
    }

    /// One line: its exact text and, for a setting, the parsed assignment.
    struct Line: Equatable, Sendable {
        var text: String
        var assignment: Assignment?
    }

    let path: String
    private(set) var lines: [Line]

    init(path: String, text: String) {
        self.path = path
        lines = text.split(separator: "\n", omittingEmptySubsequences: false).map {
            Line(text: String($0), assignment: Self.parse(String($0)))
        }
    }

    /// The text of the file, with the same line breaks.
    var text: String { lines.map(\.text).joined(separator: "\n") }

    /// The value of the only plain assignment of `name`.
    /// - Throws: `DevFailure.checkFailed` when the setting is missing, assigned twice, or conditional.
    func value(of name: String) throws -> String {
        let index = try assignmentIndex(of: name)
        return lines[index].assignment?.value ?? ""
    }

    /// Replaces the value of the only plain assignment of `name`. Only that line changes.
    mutating func set(_ name: String, to value: String) throws {
        guard !value.isEmpty, !value.contains("\n"), !value.contains("//"), !value.contains(";") else {
            throw DevFailure.usage("The value of \(name) must be one line without a comment.")
        }
        let index = try assignmentIndex(of: name)
        lines[index] = Line(
            text: "\(name) = \(value)", assignment: Assignment(name: name, condition: nil, value: value))
    }

    private func assignmentIndex(of name: String) throws -> Int {
        let matches = lines.indices.filter { lines[$0].assignment?.name == name }
        guard let index = matches.first else {
            throw DevFailure.checkFailed("\(path) does not set \(name).")
        }
        guard matches.count == 1, lines[index].assignment?.condition == nil else {
            throw DevFailure.checkFailed("\(path) must set \(name) exactly once, without a condition.")
        }
        return index
    }

    /// The assignment on one line, or nil for a comment, an include, an empty line, or other text.
    static func parse(_ text: String) -> Assignment? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // A condition such as `[config=Release]` contains `=` too, so the assignment starts after it.
        let firstEquals = trimmed.firstIndex(of: "=") ?? trimmed.endIndex
        let hasCondition = trimmed[..<firstEquals].contains("[")
        let nameEnd = hasCondition ? (trimmed.firstIndex(of: "]") ?? trimmed.startIndex) : trimmed.startIndex
        guard let equals = trimmed[nameEnd...].firstIndex(of: "="), !trimmed.hasPrefix("//"),
            !trimmed.hasPrefix("#")
        else { return nil }
        var name = trimmed[..<equals].trimmingCharacters(in: .whitespaces)
        var condition: String?
        if let open = name.firstIndex(of: "["), name.hasSuffix("]") {
            condition = String(name[name.index(after: open)..<name.index(before: name.endIndex)])
            name = String(name[..<open])
        }
        guard isSettingName(name) else { return nil }
        var value = trimmed[trimmed.index(after: equals)...]
        if let comment = value.range(of: "//") {
            value = value[..<comment.lowerBound]
        }
        var cleaned = value.trimmingCharacters(in: .whitespaces)
        if cleaned.hasSuffix(";") {
            cleaned.removeLast()
        }
        return Assignment(name: name, condition: condition, value: cleaned.trimmingCharacters(in: .whitespaces))
    }

    /// A build setting name: a letter or `_`, then ASCII letters, digits, or `_`.
    static func isSettingName(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, first == "_" || (first.isASCII && first.properties.isAlphabetic)
        else { return false }
        return text.unicodeScalars.allSatisfy {
            $0 == "_" || ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)))
        }
    }
}
