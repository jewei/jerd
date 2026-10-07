import Foundation
import os

@testable import JerdDevKit

/// Records each invocation and answers with a scripted result. It never starts a process.
final class RecordingProcessRunner: ProcessRunning {
    typealias Responder = @Sendable (Invocation) throws -> InvocationResult

    private let invocations = OSAllocatedUnfairLock(initialState: [Invocation]())
    private let responder: Responder

    /// - Parameter responder: The answer for each invocation. The default succeeds with no output.
    init(responder: @escaping Responder = { InvocationResult(commandLine: $0.commandLine, status: 0) }) {
        self.responder = responder
    }

    func run(_ invocation: Invocation, output: OutputMode) async throws -> InvocationResult {
        invocations.withLock { $0.append(invocation) }
        return try responder(invocation)
    }

    var recorded: [Invocation] { invocations.withLock { $0 } }
}
