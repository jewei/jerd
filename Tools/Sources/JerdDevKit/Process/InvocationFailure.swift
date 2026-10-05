/// Why an external command did not succeed. Every case keeps the command line for the report.
enum InvocationFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case launchFailed(commandLine: String, reason: String)
    case timedOut(commandLine: String, limit: Duration)
    case exited(commandLine: String, status: Int32, standardErrorTail: String)

    var commandLine: String {
        switch self {
        case .launchFailed(let commandLine, _), .timedOut(let commandLine, _), .exited(let commandLine, _, _):
            commandLine
        }
    }

    var description: String {
        switch self {
        case .launchFailed(let commandLine, let reason):
            return "Could not start \(commandLine): \(reason)"
        case .timedOut(let commandLine, let limit):
            return "Stopped \(commandLine) after the time limit of \(limit.formattedSeconds)."
        case .exited(let commandLine, let status, let tail):
            let detail = tail.isEmpty ? "" : "\n\(tail)"
            return "\(commandLine) failed with exit status \(status).\(detail)"
        }
    }
}

extension Duration {
    /// Whole seconds, for messages such as "120 s".
    var formattedSeconds: String {
        "\(components.seconds) s"
    }
}
