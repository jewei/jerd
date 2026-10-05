import JerdFoundation

/// Proof that a service may start: its lock is held and no previous process needs inspection.
///
/// Only `StartGate` creates one. Saving a new record requires it, so a record can never be
/// written beside a live process or without the lock.
public struct StartClearance: Sendable {
    public let location: RecordLocation
    let lock: InstanceLock

    init(location: RecordLocation, lock: InstanceLock) {
        self.location = location
        self.lock = lock
    }

    /// True while the lock that produced this clearance is still held.
    public var isValid: Bool { lock.guards(location.lockFile) }
}
