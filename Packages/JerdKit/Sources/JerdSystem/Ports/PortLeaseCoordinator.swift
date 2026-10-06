import Darwin
import Foundation
import JerdFoundation

/// The pure state machine of the helper's standard ports: one setup change or one acquisition at a
/// time across all connections, and at most one lease of the listeners, held by one connection.
///
/// States: `idle` → `mutating` (configure, remove, recover) → `idle`, and `idle` → `acquiring` →
/// `idle` (with or without a new lease). A setup change needs no lease. Each refusal has its own
/// message.
public struct PortLeaseCoordinator<Resource: Sendable>: Sendable {
    /// The setup changes that exclude a lease.
    public enum Mutation: String, Sendable, CaseIterable {
        case configure = "changing"
        case remove = "removing"
        case recover = "recovering"
    }

    /// What holds the standard ports now: nothing, a setup change, or a listener acquire.
    public enum Activity: Equatable, Sendable {
        case idle
        case mutating(Mutation)
        case acquiring(connection: UUID)
    }

    /// The listeners and the connection that holds them.
    public struct Lease: Sendable {
        public let connection: UUID
        public let owner: uid_t
        public let resource: Resource
    }

    /// What `beginAcquire` decided.
    public enum AcquireStart: Sendable {
        /// The same connection already holds the lease: return the same listeners.
        case existing(Resource)
        /// Check the setup, bind, then call `finishAcquire`.
        case proceed
    }

    public private(set) var activity: Activity = .idle
    public private(set) var lease: Lease?

    public init() {}

    public mutating func beginMutation(_ mutation: Mutation) throws {
        guard lease == nil else {
            throw JerdError.invalid("Stop Jerd's environment before \(mutation.rawValue) system setup.")
        }
        guard activity == .idle else { throw Self.busy }
        activity = .mutating(mutation)
    }

    public mutating func endMutation() {
        if case .mutating = activity { activity = .idle }
    }

    public mutating func beginAcquire(connection: UUID, owner: uid_t) throws -> AcquireStart {
        guard activity == .idle else { throw Self.busy }
        if let lease {
            guard lease.connection == connection, lease.owner == owner else {
                throw JerdError.unavailable("Another Jerd connection owns the standard ports.")
            }
            return .existing(lease.resource)
        }
        activity = .acquiring(connection: connection)
        return .proceed
    }

    /// Ends an acquisition. With `resource`, the lease is stored only while the connection is alive;
    /// otherwise the caller must close the resource.
    public mutating func finishAcquire(
        connection: UUID, owner: uid_t, resource: Resource?, connectionAlive: Bool
    ) throws {
        guard activity == .acquiring(connection: connection) else { return }
        activity = .idle
        guard let resource else { return }
        guard connectionAlive else { throw JerdError.unavailable("The helper connection was closed.") }
        lease = Lease(connection: connection, owner: owner, resource: resource)
    }

    /// Ends the lease of `connection`. Returns the listeners to close, or nil when it holds none.
    public mutating func release(connection: UUID) -> Resource? {
        guard let lease, lease.connection == connection else { return nil }
        self.lease = nil
        return lease.resource
    }

    private static var busy: JerdError { .unavailable("System setup is in progress. Retry shortly.") }
}
