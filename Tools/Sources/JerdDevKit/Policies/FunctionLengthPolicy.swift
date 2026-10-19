/// Functions stay under 40 lines (AGENTS.md, Code rules). A function, initializer, subscript, or
/// deinitializer counts from its declaration line through its closing brace. Attributes on their
/// own lines and doc comments do not count. Computed properties, such as a SwiftUI `body`, are not
/// functions.
enum FunctionLengthPolicy {
    /// The longest function that the policy accepts.
    static let lineLimit = 39

    /// A computed value, because `Regex` is not `Sendable`. A `.` before `init` is a call.
    private static var declaration: Regex<Substring> {
        #/(?:^|[^.\w])(?:func\s|init[?!]?\s*[(<]|deinit\b|subscript\s*[(<])/#
    }

    /// The start of a line that begins another member.
    private static var member: Regex<Substring> {
        #/^\s*(?:@|(?:var|let|func|init|deinit|subscript|case|static|public|package|private|fileprivate|internal|typealias|associatedtype|struct|class|enum|actor|extension|protocol|nonisolated|mutating|override|final)\b)/#
    }

    /// - Parameter files: Paths relative to the root, with their text.
    static func findings(files: [(path: String, text: String)]) -> [PolicyFinding] {
        files.flatMap { file in
            functionLengths(in: file.text).compactMap { function in
                guard function.lines > lineLimit else { return nil }
                return PolicyFinding(
                    file: file.path,
                    message: "line \(function.line): the function has \(function.lines) lines; "
                        + "keep functions under \(lineLimit + 1) lines.")
            }
        }
    }

    /// The first line (1-based) and the line count of each function with a body.
    static func functionLengths(in text: String) -> [(line: Int, lines: Int)] {
        let lines = SwiftCodeText(text).lines
        return lines.indices.compactMap { start in
            guard isDeclaration(lines[start]), let end = bodyEnd(in: lines, from: start) else { return nil }
            return (start + 1, end - start + 1)
        }
    }

    /// The index of the line with the closing brace of the body, or nil for a requirement without a
    /// body, such as a protocol member. Braces inside the parameter list, such as a default
    /// closure, do not open the body.
    static func bodyEnd(in lines: [String], from start: Int) -> Int? {
        var depth = 0
        var parentheses = 0
        for index in start..<lines.count {
            if index > start, depth == 0, parentheses == 0, lines[index].contains(member) { return nil }
            for character in lines[index] {
                switch character {
                case "(" where depth == 0: parentheses += 1
                case ")" where depth == 0: parentheses -= 1
                case "{" where parentheses == 0: depth += 1
                case "}" where parentheses == 0:
                    if depth == 0 { return nil }
                    depth -= 1
                    if depth == 0 { return index }
                default: break
                }
            }
        }
        return nil
    }

    static func isDeclaration(_ line: String) -> Bool {
        // A plain search first: `Regex` is slow, and most lines have none of these words.
        guard line.contains("func") || line.contains("init") || line.contains("subscript") else { return false }
        return line.contains(declaration)
    }
}
