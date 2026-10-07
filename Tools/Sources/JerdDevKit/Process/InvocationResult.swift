/// The exit status and captured output of a finished command. A command that passed its time limit
/// is a result too, so that its captured output can explain where it stopped.
struct InvocationResult: Equatable, Sendable {
    var commandLine: String
    var status: Int32
    var standardOutput: String
    var standardError: String
    /// The time limit that the command passed before the runner stopped it, or `nil`.
    var exceededTimeLimit: Duration?

    init(
        commandLine: String,
        status: Int32,
        standardOutput: String = "",
        standardError: String = "",
        exceededTimeLimit: Duration? = nil
    ) {
        self.commandLine = commandLine
        self.status = status
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exceededTimeLimit = exceededTimeLimit
    }

    var succeeded: Bool { status == 0 && exceededTimeLimit == nil }

    /// How the command failed, for messages such as "JerdKit tests failed with exit status 1."
    var failureSummary: String {
        if let limit = exceededTimeLimit {
            return "stopped at the time limit of \(limit.formattedSeconds)"
        }
        return "failed with exit status \(status)"
    }

    /// Returns `self` when the command succeeded, otherwise throws the typed failure.
    func checked() throws(InvocationFailure) -> InvocationResult {
        if let limit = exceededTimeLimit {
            throw .timedOut(commandLine: commandLine, limit: limit)
        }
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
