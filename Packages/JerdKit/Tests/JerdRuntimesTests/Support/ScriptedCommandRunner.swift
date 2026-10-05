import Foundation
import JerdFoundation
import JerdProcess
import os

/// A command runner whose answers come from a closure. It records every request.
final class ScriptedCommandRunner: CommandRunning, Sendable {
    typealias Script = @Sendable (ProcessRequest) async throws -> CommandResult

    private let script: Script
    private let log = OSAllocatedUnfairLock(initialState: [ProcessRequest]())

    init(_ script: @escaping Script = { _ in CommandResult(status: 0, output: "") }) {
        self.script = script
    }

    var requests: [ProcessRequest] { log.withLock { $0 } }

    /// The executable names and arguments of every request, for compact assertions.
    var commandLines: [[String]] {
        requests.map { [$0.executable.lastPathComponent] + $0.arguments }
    }

    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        log.withLock { $0.append(request) }
        return try await script(request)
    }
}
