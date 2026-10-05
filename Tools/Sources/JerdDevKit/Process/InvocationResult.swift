/// The exit status and captured output of a finished command.
public struct InvocationResult: Equatable, Sendable {
    public var commandLine: String
    public var status: Int32
    public var standardOutput: String
    public var standardError: String

    public init(commandLine: String, status: Int32, standardOutput: String = "", standardError: String = "") {
        self.commandLine = commandLine
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
    }

    public var succeeded: Bool { status == 0 }

    /// Returns `self` when the command succeeded, otherwise throws the typed failure.
    public func checked() throws(InvocationFailure) -> InvocationResult {
        guard succeeded else {
            throw .exited(commandLine: commandLine, status: status, standardErrorTail: Self.tail(of: standardError))
        }
        return self
    }

    /// The last lines of an error stream: enough to explain a failure without flooding the report.
    static func tail(of text: String, lineLimit: Int = 20) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        return lines.suffix(lineLimit).joined(separator: "\n")
    }
}
