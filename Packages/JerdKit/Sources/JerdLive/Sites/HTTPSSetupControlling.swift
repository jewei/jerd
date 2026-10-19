import JerdWeb

/// The system setup gateway calls that the Sites port uses. `SystemSetupGateway` is the live type.
package protocol HTTPSSetupControlling: Sendable {
    func status() async throws -> HTTPSSetupStatus
    /// Stops the run, removes the hosts section and the CA trust, and records the removal.
    func removeSetup() async throws
    /// Jerd's CA for `.test` names that would replace the CA that Caddy made.
    func prepareCAMigration() async throws -> InstallationAuthority
    /// Stops the run and replaces the CA that Caddy made with Jerd's CA for `.test` names.
    func migrateCA() async throws
}

extension SystemSetupGateway: HTTPSSetupControlling {}
