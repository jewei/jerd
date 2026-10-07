import os

/// Collects progress messages from any thread, for assertions after the work ends.
final class ProgressLog: Sendable {
    private let messages = OSAllocatedUnfairLock(initialState: [String]())

    func append(_ message: String) { messages.withLock { $0.append(message) } }

    var all: [String] { messages.withLock { $0 } }
}
