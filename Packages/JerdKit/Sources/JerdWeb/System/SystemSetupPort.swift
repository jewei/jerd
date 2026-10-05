import JerdProcess

/// The privileged helper as the web layer needs it. JerdLive implements it with the JerdSystem client.
///
/// The helper never receives project paths and never runs a process.
public protocol SystemSetupPort: Sendable {
    /// The approved setup. An absent setup is an empty status.
    func status() async throws -> HTTPSSetupStatus
    /// Asks for approval, then writes the hosts section and the CA trust for exactly this registration.
    func configure(_ registration: HTTPSRegistration) async throws
    /// The helper's bound `127.0.0.1:80` and `127.0.0.1:443` listeners, leased to this app.
    func acquireListeners() async throws -> InheritedListeners
    /// Ends the lease. The caller closes its own copies of the descriptors.
    func releaseListeners() async
    /// Removes Jerd's hosts section and the CA trust.
    func removeSetup() async throws
}
