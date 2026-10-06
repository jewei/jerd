import Darwin
import Foundation
import JerdFoundation
import JerdSystem

extension HelperService {
    /// Gives the standard-port listeners to `connection`. The same connection gets the same listeners
    /// again; another connection is refused while the lease exists.
    ///
    /// The setup must be ready for serving: hosts and trust configured with the server TLS policy,
    /// no interrupted or running transaction. A connection that closes while the
    /// setup is checked gets no lease.
    func acquire(owner: uid_t, connection: UUID, lifetime: SessionLifetime) async throws -> LoopbackListenerPair {
        try lifetime.check()
        if case .existing(let pair) = try beginAcquire(connection: connection, owner: owner) { return pair }
        var bound: LoopbackListenerPair?
        do {
            try Self.requireReady(try await setupStatus(owner: owner))
            try lifetime.check()
            let pair = try await bindListeners()
            bound = pair
            try finishAcquire(connection: connection, owner: owner, pair: pair, alive: lifetime.isValid)
            return pair
        } catch {
            // Without a pair this only ends the acquisition; it cannot throw.
            try? finishAcquire(connection: connection, owner: owner, pair: nil, alive: false)
            bound?.close()
            throw error
        }
    }

    static func requireReady(_ status: SystemSetupStatus) throws {
        if status.operationInProgress != nil {
            throw JerdError.unavailable("System setup is in progress. Retry shortly.")
        }
        if status.recovery != nil {
            throw JerdError.unavailable("Recover the interrupted HTTPS setup in Advanced before starting sites.")
        }
        guard status.hostsConfigured, status.trustConfigured else {
            throw JerdError.unavailable("Approved host and certificate setup is required.")
        }
        guard status.trustPolicy == .serverTLS else {
            throw JerdError.unavailable("Approve HTTPS setup again so that browsers trust the Jerd CA.")
        }
    }
}
