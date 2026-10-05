/// Writes the tool's own lines in one style: `==>` step headers, indented details, and `$` command
/// lines in verbose mode. Errors go to standard error; everything else goes to standard output.
struct Console: Sendable {
    let output: any TextOutput
    let verbose: Bool

    func step(_ title: String) {
        output.write("==> \(title)\n", to: .standardOutput)
    }

    func detail(_ text: String) {
        output.write(Self.indented(text), to: .standardOutput)
    }

    func success(_ text: String) {
        output.write(Self.indented("ok: \(text)"), to: .standardOutput)
    }

    func warning(_ text: String) {
        output.write(Self.indented("warning: \(text)"), to: .standardOutput)
    }

    func error(_ text: String) {
        output.write(Self.indented("error: \(text)"), to: .standardError)
    }

    /// Shows the exact command line in verbose mode, so that a user can run it alone.
    func command(_ invocation: Invocation) {
        guard verbose else { return }
        output.write(Self.indented("$ \(invocation.commandLine)"), to: .standardOutput)
    }

    /// Prints text as it is, for example a help message.
    func plain(_ text: String) {
        output.write(text.hasSuffix("\n") ? text : text + "\n", to: .standardOutput)
    }

    static func indented(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "    \($0)" }
            .joined(separator: "\n") + "\n"
    }
}
