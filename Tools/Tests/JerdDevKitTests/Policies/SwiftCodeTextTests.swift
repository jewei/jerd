import Foundation
import Testing

@testable import JerdDevKit

@Suite("Swift code text")
struct SwiftCodeTextTests {
    @Test("blanks comments and strings and keeps each line")
    func blanksCommentsAndStrings() {
        let lines = SwiftCodeText("let a = \"{\" // }\n/* { /* } */ } */ b\nc").lines
        #expect(lines.map { $0.trimmingCharacters(in: .whitespaces) } == ["let a =", "b", "c"])
        #expect(lines[0].count == "let a = \"{\" // }".count)
    }

    @Test("keeps the code of an interpolation and blanks the strings inside it")
    func keepsInterpolatedCode() {
        let line = SwiftCodeText(#"let a = "x\(f({ "}" }))y" + b"#).lines[0]
        #expect(line.split(separator: " ") == ["let", "a", "=", "f({", "})", "+", "b"])
    }

    @Test("handles multiline and raw strings")
    func handlesMultilineAndRawStrings() {
        let text = "let a = \"\"\"\n  { \"\n  \"\"\"\nlet b = #\"\"}\"#\nc"
        let lines = SwiftCodeText(text).lines.map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines == ["let a =", "", "", "let b =", "c"])
    }
}
