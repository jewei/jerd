import Foundation
import JerdProcess
import os

/// A command runner that answers from a handler and records each request.
final class ScriptedCommands: CommandRunning {
    typealias Handler = @Sendable (ProcessRequest) async throws -> CommandResult

    private let handler: Handler
    private let calls = OSAllocatedUnfairLock<[ProcessRequest]>(initialState: [])

    init(handler: @escaping Handler) { self.handler = handler }

    /// Every request, in order.
    var requests: [ProcessRequest] { calls.withLock { $0 } }

    /// The requests of one executable name, for example "lsof" or "initdb".
    func requests(named name: String) -> [ProcessRequest] {
        requests.filter { $0.executable.lastPathComponent == name }
    }

    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        calls.withLock { $0.append(request) }
        return try await handler(request)
    }
}
