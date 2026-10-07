import Foundation
import JerdProcess
import os

/// A command runner that answers from a handler and records each request.
package final class ScriptedCommands: CommandRunning {
    package typealias Handler = @Sendable (ProcessRequest) async throws -> CommandResult

    private let handler: Handler
    private let calls = OSAllocatedUnfairLock<[ProcessRequest]>(initialState: [])

    package init(handler: @escaping Handler) { self.handler = handler }

    /// Every request, in order.
    package var requests: [ProcessRequest] { calls.withLock { $0 } }

    /// The requests of one executable name, for example "lsof" or "server".
    package func requests(named name: String) -> [ProcessRequest] {
        requests.filter { $0.executable.lastPathComponent == name }
    }

    package func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        calls.withLock { $0.append(request) }
        return try await handler(request)
    }
}
