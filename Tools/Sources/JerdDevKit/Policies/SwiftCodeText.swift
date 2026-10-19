/// Swift source with every comment and string literal replaced by spaces, so that a policy can
/// match braces and names without false hits in text. Line breaks stay, so line numbers match the
/// source. Interpolated code inside a string stays code.
struct SwiftCodeText {
    /// The code-only lines, one for each source line.
    private(set) var lines: [String] = []

    private var output: [Character] = []
    /// One entry for each open context, innermost last.
    private var contexts: [Context] = []

    private enum Context {
        case blockComment
        case string(hashes: Int, multiline: Bool)
        /// Code inside `\(…)`; the count is the depth of open parentheses inside it.
        case interpolation(parentheses: Int)
    }

    init(_ text: String) {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            index = scan(characters, at: index)
        }
        lines = String(output).components(separatedBy: "\n")
    }

    /// Handles the character at `index` and returns the index of the next one to read.
    private mutating func scan(_ characters: [Character], at index: Int) -> Int {
        switch contexts.last {
        case .blockComment: return scanBlockComment(characters, at: index)
        case .string(let hashes, let multiline):
            return scanString(characters, at: index, hashes: hashes, multiline: multiline)
        case .interpolation, nil: return scanCode(characters, at: index)
        }
    }

    private mutating func scanCode(_ characters: [Character], at index: Int) -> Int {
        let character = characters[index]
        if starts(characters, at: index, with: "//") {
            var end = index
            while end < characters.count, characters[end] != "\n" { end += 1 }
            blank(end - index)
            return end
        }
        if starts(characters, at: index, with: "/*") {
            contexts.append(.blockComment)
            blank(2)
            return index + 2
        }
        if let opening = stringOpening(characters, at: index) {
            contexts.append(.string(hashes: opening.hashes, multiline: opening.multiline))
            blank(opening.length)
            return index + opening.length
        }
        if case .interpolation(0) = contexts.last, character == ")" {
            contexts.removeLast()
            blank(1)
            return index + 1
        }
        trackParentheses(character)
        output.append(character)
        return index + 1
    }

    private mutating func trackParentheses(_ character: Character) {
        guard case .interpolation(let depth) = contexts.last else { return }
        if character == "(" {
            contexts[contexts.count - 1] = .interpolation(parentheses: depth + 1)
        } else if character == ")", depth > 0 {
            contexts[contexts.count - 1] = .interpolation(parentheses: depth - 1)
        }
    }

    private mutating func scanBlockComment(_ characters: [Character], at index: Int) -> Int {
        if starts(characters, at: index, with: "/*") {
            contexts.append(.blockComment)
            blank(2)
            return index + 2
        }
        if starts(characters, at: index, with: "*/") {
            contexts.removeLast()
            blank(2)
            return index + 2
        }
        blankOrBreak(characters[index])
        return index + 1
    }

    private mutating func scanString(_ characters: [Character], at index: Int, hashes: Int, multiline: Bool) -> Int {
        let escape = "\\" + String(repeating: "#", count: hashes)
        if starts(characters, at: index, with: escape + "(") {
            contexts.append(.interpolation(parentheses: 0))
            blank(escape.count + 1)
            return index + escape.count + 1
        }
        if starts(characters, at: index, with: escape), index + escape.count < characters.count {
            blank(escape.count)
            blankOrBreak(characters[index + escape.count])
            return index + escape.count + 1
        }
        let closing = (multiline ? "\"\"\"" : "\"") + String(repeating: "#", count: hashes)
        if starts(characters, at: index, with: closing) {
            contexts.removeLast()
            blank(closing.count)
            return index + closing.count
        }
        blankOrBreak(characters[index])
        return index + 1
    }

    /// The `#…"` or `#…"""` that opens a string literal at `index`, if any.
    private func stringOpening(
        _ characters: [Character], at index: Int
    ) -> (hashes: Int, multiline: Bool, length: Int)? {
        var end = index
        while end < characters.count, characters[end] == "#" { end += 1 }
        let hashes = end - index
        guard end < characters.count, characters[end] == "\"" else { return nil }
        let multiline = starts(characters, at: end, with: "\"\"\"")
        return (hashes, multiline, hashes + (multiline ? 3 : 1))
    }

    private func starts(_ characters: [Character], at index: Int, with prefix: String) -> Bool {
        let prefix = Array(prefix)
        guard index + prefix.count <= characters.count else { return false }
        return Array(characters[index..<index + prefix.count]) == prefix
    }

    private mutating func blank(_ count: Int) {
        output.append(contentsOf: repeatElement(" ", count: count))
    }

    private mutating func blankOrBreak(_ character: Character) {
        output.append(character == "\n" ? "\n" : " ")
    }
}
