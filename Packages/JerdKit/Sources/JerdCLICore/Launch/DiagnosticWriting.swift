import Foundation

/// Writes launcher errors and warnings for the user. The live writer uses standard error.
package protocol DiagnosticWriting: Sendable {
    /// Writes one line. The writer adds the line end.
    func writeLine(_ line: String)
}

/// The live diagnostic writer: standard error, so the command output stays clean.
package struct StandardErrorWriter: DiagnosticWriting {
    package init() {}

    package func writeLine(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
