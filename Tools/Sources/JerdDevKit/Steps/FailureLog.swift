import Foundation

/// Keeps the complete output of a failed quiet command. Quiet mode prints only selected lines, so the
/// log is the place for the rest, for example linker details or where a command stopped at its time
/// limit. CI can upload `.build/logs` as an artifact.
enum FailureLog {
    static let tailLineCount = 50

    /// Writes `.build/logs/<name>.log` and prints its path. With `showsTail`, it also prints the last
    /// lines of the output. In verbose mode the output is already on the screen, so it does nothing.
    static func report(_ result: InvocationResult, name: String, showsTail: Bool, context: DevContext) {
        guard !context.console.verbose else { return }
        let file = context.repository.logs.appending(path: "\(name).log")
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text(of: result).utf8).write(to: file, options: .atomic)
            context.console.detail("The full log is in \(context.repository.relativePath(of: file)).")
        } catch {
            context.console.warning("Could not write \(file.path): \(error.localizedDescription)")
        }
        let tail = tail(of: result)
        if showsTail, !tail.isEmpty {
            context.console.detail("The last lines of the output:\n\(tail)")
        }
    }

    static func text(of result: InvocationResult) -> String {
        """
        $ \(result.commandLine)
        Result: \(result.failureSummary)
        == Standard output ==
        \(result.standardOutput)
        == Standard error ==
        \(result.standardError)
        """
    }

    /// The last lines of standard output and then of standard error, at most `tailLineCount` in all.
    static func tail(of result: InvocationResult) -> String {
        InvocationResult.tail(of: result.standardOutput + "\n" + result.standardError, lineLimit: tailLineCount)
    }
}
