/// The result of a finished command: its status and its merged standard output and error.
public struct CommandResult: Equatable, Sendable {
    /// The exit status, or 128 plus the signal number when a signal ended the command.
    public let status: Int32
    /// The first 1 MiB of output, for parsers.
    public let output: String
    /// The last 64 KiB of output, for error messages.
    public let diagnosticOutput: String

    /// Without `diagnosticOutput`, the diagnostic text is the output.
    public init(status: Int32, output: String, diagnosticOutput: String? = nil) {
        self.status = status
        self.output = output
        self.diagnosticOutput = diagnosticOutput ?? output
    }

    /// True when the status is 0.
    public var succeeded: Bool { status == 0 }
}
