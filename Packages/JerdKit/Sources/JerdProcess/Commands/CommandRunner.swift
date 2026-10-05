import Darwin
import Foundation
import JerdFoundation

/// Runs one command with its own supervisor, a deadline, and cancellation.
///
/// Output goes to a log in a new private temporary folder (mode 0700), never into the
/// command's working folder, and the folder is removed on every exit path. The timeout
/// decision is made once, from one state read, so an exit after the deadline cannot make a
/// timed-out command look successful or the reverse.
public struct CommandRunner: CommandRunning {
    /// The default command timeout.
    public static let defaultTimeout: Duration = .seconds(15)
    /// The head of the output that `CommandResult.output` keeps.
    public static let outputLimit = ProcessLogFile.commandHeadBytes
    /// The tail of the output that `CommandResult.diagnosticOutput` keeps.
    public static let diagnosticLimit = 65_536
    /// The tail characters that a timeout message shows.
    public static let timeoutDetailLimit = 4_096

    private let temporaryRoot: URL
    private let cleanupPolicy: StopPolicy

    /// - Parameters:
    ///   - temporaryRoot: where the private output folders are made.
    ///   - cleanupPolicy: how a timed-out or cancelled command and leftover group members are stopped.
    public init(
        temporaryRoot: URL = FileManager.default.temporaryDirectory, cleanupPolicy: StopPolicy = .forceful()
    ) {
        self.temporaryRoot = temporaryRoot
        self.cleanupPolicy = cleanupPolicy
    }

    public func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        let folder = try makePrivateFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = ProcessLogFile(url: folder.appendingPathComponent("output.log"), retainedHeadBytes: Self.outputLimit)
        let supervisor = ProcessSupervisor()
        let token = try await supervisor.start(request, log: log)
        let state = await supervisor.waitForExit(of: token, timeout: timeout)
        let cancelled = Task.isCancelled
        // Also after an exit: this reaps the leader and stops members left in its group.
        let cleanup = await supervisor.stop(token, policy: cleanupPolicy)
        if cancelled { throw CancellationError() }
        let output = try log.readHead(limit: Self.outputLimit)
        let diagnostics = try log.readTail(limit: Self.diagnosticLimit)
        if state.isRunning {
            throw JerdError.timedOut(
                "Command timed out: \(request.executable.path)\n\(diagnostics.suffix(Self.timeoutDetailLimit))")
        }
        guard let status = state.exitCode, cleanup != .notOwned else {
            throw JerdError.processFailed("The result of \(request.executable.path) is unknown. Run the command again.")
        }
        return CommandResult(status: status, output: output, diagnosticOutput: diagnostics)
    }

    private func makePrivateFolder() throws -> URL {
        var template = Array(temporaryRoot.appendingPathComponent("jerd-command-XXXXXX").path.utf8CString)
        let created = template.withUnsafeMutableBufferPointer { buffer in
            buffer.baseAddress.flatMap { mkdtemp($0) }.map { String(cString: $0) }
        }
        guard let created else {
            throw JerdError.unavailable("Cannot create a private command folder (\(SystemError.describe(errno))).")
        }
        return URL(fileURLWithPath: created, isDirectory: true)
    }
}
