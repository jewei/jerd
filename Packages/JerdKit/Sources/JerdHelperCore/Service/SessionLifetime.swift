import JerdFoundation
import os

/// Whether the XPC connection of a session is still open. Invalidation is immediate and final.
final class SessionLifetime: Sendable {
    private let valid = OSAllocatedUnfairLock(initialState: true)

    var isValid: Bool { valid.withLock { $0 } }

    func invalidate() { valid.withLock { $0 = false } }

    /// Throws `.unavailable` once the connection is closed.
    func check() throws {
        guard isValid else { throw JerdError.unavailable("The helper connection was closed.") }
    }
}
