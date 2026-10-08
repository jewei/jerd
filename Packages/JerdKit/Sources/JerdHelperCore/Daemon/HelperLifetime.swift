import os

/// The open connections of the helper and its exit decision, behind one lock.
///
/// The listener delegate counts connections synchronously on the XPC queue, so this is a lock,
/// not an actor. Every open and close changes `generation`, so the idle monitor sees a
/// connection that came and went between two checks. Once `beginExit` succeeds, new connections
/// are refused; the client gets a closed connection and its retry makes launchd start the helper
/// again.
final class HelperLifetime: Sendable {
    /// The state that one idle check reads.
    struct Snapshot: Equatable, Sendable {
        var connections = 0
        var generation = 0
        var isExiting = false
    }

    /// One accepted connection. `close()` counts it once, also when XPC calls both close handlers.
    final class Ticket: Sendable {
        private let lifetime: HelperLifetime
        private let open = OSAllocatedUnfairLock(initialState: true)

        fileprivate init(_ lifetime: HelperLifetime) { self.lifetime = lifetime }

        func close() {
            let wasOpen = open.withLock { current -> Bool in
                defer { current = false }
                return current
            }
            if wasOpen { lifetime.closed() }
        }
    }

    private let state = OSAllocatedUnfairLock(initialState: Snapshot())

    var snapshot: Snapshot { state.withLock { $0 } }

    /// Counts a new connection. Returns nil while the helper exits; the caller then refuses it.
    func open() -> Ticket? {
        let accepted = state.withLock { current -> Bool in
            guard !current.isExiting else { return false }
            current.connections += 1
            current.generation += 1
            return true
        }
        return accepted ? Ticket(self) : nil
    }

    /// Starts the exit when nothing connected since `generation` was read. From now on every new
    /// connection is refused.
    func beginExit(expecting generation: Int) -> Bool {
        state.withLock { current in
            guard !current.isExiting, current.connections == 0, current.generation == generation else { return false }
            current.isExiting = true
            return true
        }
    }

    /// Accepts connections again, after a last check found work.
    func cancelExit() {
        state.withLock { $0.isExiting = false }
    }

    private func closed() {
        state.withLock { current in
            current.connections = max(0, current.connections - 1)
            current.generation += 1
        }
    }
}
