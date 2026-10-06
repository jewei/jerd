import JerdSystem

/// The calls of the privileged helper client that the live ports use. `HelperClient` is the live
/// type; tests use a recording fake, so no test talks to a real helper.
package protocol HelperControlling: Sendable {
    func status() async throws -> HelperStatus
    func configure(
        hostnames: ValidatedHostnames, caCertificate: JerdSystem.InstallationCertificate, policy: CertificateTrustPolicy
    ) async throws
    func acquireListeners() async throws -> LoopbackListenerPair
    func releaseListeners() async
    func removeSetup() async throws
    func recover(report: SystemRecoveryStatus, action: SystemRecoveryAction) async throws
    /// Registers the helper daemon after the user approved HTTPS setup.
    func approve() async throws
    func reconnect() async throws
    func unregister() async throws
    func invalidate() async
}

extension HelperClient: HelperControlling {}
