/// Source files stay at or under 300 lines (AGENTS.md, Code rules). A longer type splits into
/// `Type+Topic.swift` extensions.
enum SourceLengthPolicy {
    static let lineLimit = 300

    /// The folders whose Swift sources the policy checks. Tests may be longer.
    static let checkedFolders = ["Packages/JerdKit/Sources", "Apps", "Tools/Sources"]

    /// - Parameter files: Paths relative to the root, with their text.
    static func findings(files: [(path: String, text: String)]) -> [PolicyFinding] {
        files.compactMap { file in
            let count = lineCount(of: file.text)
            guard count > lineLimit else { return nil }
            return PolicyFinding(file: file.path, message: "\(count) lines; the limit is \(lineLimit).")
        }
    }

    /// The number of lines as an editor shows them. A final line break does not start a new line.
    static func lineCount(of text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        let breaks = text.utf8.reduce(0) { $1 == UInt8(ascii: "\n") ? $0 + 1 : $0 }
        return text.utf8.last == UInt8(ascii: "\n") ? breaks : breaks + 1
    }
}
