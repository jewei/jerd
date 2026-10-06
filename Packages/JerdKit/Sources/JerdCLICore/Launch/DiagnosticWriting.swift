import Foundation

/// Writes launcher errors and warnings for the user. The live writer uses standard error.
public protocol DiagnosticWriting: Sendable {
    /// Writes one line. The writer adds the line end.
    func writeLine(_ line: String)
}

/// The live diagnostic writer: standard error, so the command output stays clean.
public struct StandardErrorWriter: DiagnosticWriting {
    public init() {}

    public func writeLine(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
