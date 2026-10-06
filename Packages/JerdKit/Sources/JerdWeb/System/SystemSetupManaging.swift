/// Changes the approved HTTPS setup. The site change transaction depends on this role so tests
/// can use a fake.
public protocol SystemSetupManaging: Sendable {
    func status() async throws -> HTTPSSetupStatus
    /// This installation's CA, or nil when its ID or `root.crt` is absent.
    func localAuthority() async throws -> InstallationAuthority?
    /// Creates the installation CA when needed and builds the approval for `hostnames`.
    func prepare(hostnames: [String], caddy: CaddyRuntime) async throws -> HTTPSSetup
    /// Stops the run, then sends the approved registration to the helper.
    func apply(_ setup: HTTPSSetup) async throws
    /// Stops the run, then removes `hostnames` from the approved set and keeps the rest.
    func removeHostnames(_ hostnames: Set<String>) async throws
    /// Stops the run, then makes the helper match `status` again.
    func restore(_ status: HTTPSSetupStatus) async throws
    /// Stops the run, then removes the hosts section and the CA trust.
    func removeSetup() async throws
}
