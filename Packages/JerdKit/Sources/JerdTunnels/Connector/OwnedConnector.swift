import JerdFoundation

/// A running connector with the lock and the run record that protect its instance folder.
struct OwnedConnector: Sendable {
    let handle: TunnelConnectorHandle
    /// Held from before the launch until the process stopped and its record is gone.
    let lock: InstanceLock
    let record: RecordLocation
}
