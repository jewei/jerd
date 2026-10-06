import JerdWeb

/// The system setup gateway calls that the Sites port uses. `SystemSetupGateway` is the live type.
package protocol HTTPSSetupControlling: Sendable {
    func status() async throws -> HTTPSSetupStatus
    /// Stops the run, removes the hosts section and the CA trust, and records the removal.
    func removeSetup() async throws
}

extension SystemSetupGateway: HTTPSSetupControlling {}
