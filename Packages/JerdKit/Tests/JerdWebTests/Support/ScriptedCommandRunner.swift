import Foundation
import JerdProcess
import os

/// A command runner that records every request and answers with a script.
final class ScriptedCommandRunner: CommandRunning {
    typealias Script = @Sendable (ProcessRequest) async throws -> CommandResult

    private let script: Script
    private let calls = OSAllocatedUnfairLock<[ProcessRequest]>(initialState: [])

    init(_ script: @escaping Script = { _ in CommandResult(status: 0, output: "") }) {
        self.script = script
    }

    var requests: [ProcessRequest] { calls.withLock { $0 } }

    /// The argument lists of every request, for compact checks.
    var arguments: [[String]] { requests.map(\.arguments) }

    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        calls.withLock { $0.append(request) }
        return try await script(request)
    }
}
