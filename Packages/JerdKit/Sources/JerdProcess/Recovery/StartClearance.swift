import JerdFoundation

/// Proof that a service may start: its lock is held and no previous process needs inspection.
///
/// Only `StartGate` creates one. Saving a new record requires it and the held lock, and the save
/// refuses when a record already exists, so a record can never be written without the lock or over
/// the record of a process that may still run. One clearance can serve several starts in a row
/// (setup phases), as long as each stopped process had its record removed.
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
