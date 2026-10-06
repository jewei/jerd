import Foundation

/// Runs the commands of a release through `ProcessRunning`, each with its own time limit (fixes
/// spec G 8.1 #14 and #15: no command runs without a limit or outside the runner).
///
/// A command with a log keeps its complete output in the candidate folder. Standard output and
/// standard error stay separate, so a parser reads only the stream it expects.
struct ReleaseShell: Sendable {
    let context: DevContext

    var repository: Repository { context.repository }
    var console: Console { context.console }

    /// Runs a command and returns its result, also when it failed.
    func result(
        _ executable: URL, _ arguments: [String], limit: Duration, log: URL? = nil,
        environment: [String: String]? = nil, directory: URL? = nil
    ) async throws -> InvocationResult {
        let invocation = Invocation(
            executable: executable, arguments: arguments, environment: environment,
            workingDirectory: directory ?? repository.root, timeout: limit)
        let result = try await context.run(invocation, output: context.console.verbose ? .stream : .capture)
        if let log {
            try Self.append(result, to: log)
        }
        return result
    }

    /// Runs a command and requires success.
    /// - Throws: `DevFailure.checkFailed` that names the log, or `InvocationFailure` without a log.
    @discardableResult
    func run(
        _ executable: URL, _ arguments: [String], limit: Duration, log: URL? = nil,
        environment: [String: String]? = nil, directory: URL? = nil
    ) async throws -> InvocationResult {
        let result = try await result(
            executable, arguments, limit: limit, log: log, environment: environment, directory: directory)
        guard result.succeeded else {
            guard let log else { return try result.checked() }
            let name = executable.lastPathComponent
            throw DevFailure.checkFailed(
                "\(name) \(result.failureSummary). See \(repository.relativePath(of: log)).")
        }
        return result
    }

    /// The trimmed standard output of a successful command.
    func output(
        _ executable: URL, _ arguments: [String], limit: Duration, environment: [String: String]? = nil
    ) async throws -> String {
        try await run(executable, arguments, limit: limit, environment: environment)
            .standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    func xcrun(_ arguments: [String], limit: Duration, log: URL? = nil) async throws -> InvocationResult {
        try await run(context.toolchain.xcrun, arguments, limit: limit, log: log)
    }

    @discardableResult
    func git(_ arguments: [String], environment: [String: String]? = nil) async throws -> String {
        try await output(context.toolchain.git, arguments, limit: TimeLimit.git, environment: environment)
    }

    /// The GitHub CLI. Only publication needs it.
    @discardableResult
    func gh(_ arguments: [String], limit: Duration = TimeLimit.gitHub) async throws -> String {
        guard let gh = context.toolchain.gh else {
            throw DevFailure.missingPrerequisite(Prerequisite.gitHubCLI.missingMessage)
        }
        return try await output(gh, arguments, limit: limit)
    }

    /// A tool of the resolved Sparkle package, for example `sign_update`.
    func sparkleTool(_ name: String) throws -> URL {
        let tool = repository.sparkleTools.appending(path: name)
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw DevFailure.missingPrerequisite(
                "The Sparkle tool \(name) is missing in .build/SourcePackages. Run ./dev build once to resolve it.")
        }
        return tool
    }

    static func append(_ result: InvocationResult, to log: URL) throws {
        let text = FailureLog.text(of: result) + "\n"
        if let handle = try? FileHandle(forWritingTo: log) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try Data(text.utf8).write(to: log)
        }
    }
}
