import Foundation
import JerdProcess
import os

/// A command runner that answers `lsof` from a fake listener table and every other command from
/// a handler. It records each request.
final class ScriptedCommands: CommandRunning {
    typealias Handler = @Sendable (ProcessRequest) async throws -> CommandResult

    private let handler: Handler
    private let lsof: FakeLsof?
    private let calls = OSAllocatedUnfairLock<[ProcessRequest]>(initialState: [])

    init(lsof: FakeLsof? = nil, handler: @escaping Handler) {
        self.lsof = lsof
        self.handler = handler
    }

    /// Every request, in order.
    var requests: [ProcessRequest] { calls.withLock { $0 } }

    /// The requests of one executable name, for example "lsof" or "server".
    func requests(named name: String) -> [ProcessRequest] {
        requests.filter { $0.executable.lastPathComponent == name }
    }

    func run(_ request: ProcessRequest, timeout: Duration) async throws -> CommandResult {
        calls.withLock { $0.append(request) }
        if request.executable.lastPathComponent == "lsof", let lsof {
            return await lsof.answer(request.arguments)
        }
        return try await handler(request)
    }
}
