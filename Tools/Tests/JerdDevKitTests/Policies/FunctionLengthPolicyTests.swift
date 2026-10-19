import Testing

@testable import JerdDevKit

@Suite("Function length policy")
struct FunctionLengthPolicyTests {
    /// A function whose declaration and braces take `lines` lines in all.
    private func function(_ name: String = "f", lines: Int) -> String {
        "func \(name)() {\n" + String(repeating: "    x()\n", count: lines - 2) + "}\n"
    }

    @Test("accepts 39 lines and reports 40 lines with the line and the count")
    func reportsLongFunctions() {
        let text = function("a", lines: 39) + "@MainActor\n" + function("b", lines: 40)
        let findings = FunctionLengthPolicy.findings(files: [("A.swift", text)])
        #expect(
            findings == [
                PolicyFinding(
                    file: "A.swift", message: "line 41: the function has 40 lines; keep functions under 40 lines.")
            ])
    }

    @Test("counts initializers, subscripts, and deinitializers, but not calls of init")
    func countsEveryKindOfFunction() {
        let text = """
            init(a: Int) {
                self.init()
            }
            subscript(i: Int) -> Int { i }
            deinit {}
            """
        #expect(FunctionLengthPolicy.functionLengths(in: text).map(\.lines) == [3, 1, 1])
    }

    @Test("skips requirements without a body and closures in the parameters")
    func skipsRequirementsAndDefaultClosures() {
        let text = """
            protocol P {
                func a()
                var b: Int { get }
            }
            func c(
                d: () -> Int = { 1 }
            ) -> Int {
                d()
            }
            """
        #expect(FunctionLengthPolicy.functionLengths(in: text).map(\.line) == [5])
        #expect(FunctionLengthPolicy.functionLengths(in: text).map(\.lines) == [5])
    }

    @Test("ignores braces in strings and comments")
    func ignoresBracesInText() {
        let text = "func a() {\n    let b = \"}\" // }\n}\n"
        #expect(FunctionLengthPolicy.functionLengths(in: text).map(\.lines) == [3])
    }
}
