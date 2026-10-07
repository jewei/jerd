import os

/// Records named steps in order, from any task.
final class EventLog: Sendable {
    private let storage = OSAllocatedUnfairLock<[String]>(initialState: [])

    var events: [String] { storage.withLock { $0 } }

    func add(_ event: String) { storage.withLock { $0.append(event) } }
}
