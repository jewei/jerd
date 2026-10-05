import Foundation
import JerdFoundation

/// Proof that one caller has exclusive use of a stopped instance and holds its lock, for example
/// during a runtime update. Other operations of the instance are refused until the lease ends.
public struct MaintenanceLease: Sendable {
    let id: UUID
    /// True when a server process was running when the lease began.
    public let wasRunning: Bool
    let lock: InstanceLock

    /// True while the lease lock is held and guards `lockFile`.
    public func guards(_ lockFile: URL) -> Bool { lock.guards(lockFile) }
}
