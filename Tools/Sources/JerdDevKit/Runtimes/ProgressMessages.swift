import os

/// Remembers the last progress message, so that a download that reports each percent prints its
/// message only once. Progress arrives from transfer threads, so a lock protects the state.
final class ProgressMessages: Sendable {
    private let last = OSAllocatedUnfairLock<String?>(initialState: nil)

    /// True when `message` differs from the previous message.
    func isNew(_ message: String) -> Bool {
        last.withLock { previous in
            defer { previous = message }
            return previous != message
        }
    }
}
