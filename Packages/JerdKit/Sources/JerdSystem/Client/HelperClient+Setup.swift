import Foundation
import JerdFoundation

extension HelperClient {
    /// Applies the approved hostnames and CA. The consent scope also covers the current hostnames and
    /// policy of the same CA, so a rollback to them is allowed.
    public func configure(
        hostnames: ValidatedHostnames, caCertificate: InstallationCertificate, policy: CertificateTrustPolicy
    ) async throws {
        let previous = try await status().setup
        var allowed = hostnames.strings
        var policies: Set<CertificateTrustPolicy> = [policy]
        if previous.certificateDER == caCertificate.der {
            allowed += previous.hostnames
            policies.insert(previous.trustPolicy)
        }
        let request = SystemRegistrationRequest(
            installationID: caCertificate.installationID, hostnames: hostnames.strings,
            certificateDER: caCertificate.der,
            trustPolicy: policy)
        let payload = try HelperWireProtocol.encode(request)
        try await withConsent(ConsentScope(certificate: caCertificate, hostnames: allowed, policies: policies)) {
            try await self.change { proxy, reply in proxy.configureSite(payload, reply: reply) }
        }
    }

    /// Removes the hosts section, the CA, and the registration of this user.
    public func removeSetup() async throws {
        let previous = try await status().setup
        var scope: ConsentScope?
        if let id = previous.installationID, let der = previous.certificateDER, !previous.hostnames.isEmpty {
            scope = try ConsentScope(
                certificate: InstallationCertificate(installationID: id, der: der), hostnames: previous.hostnames,
                policies: [previous.trustPolicy])
        }
        try await withConsent(scope) {
            try await self.change { proxy, reply in proxy.removeSetup(reply: reply) }
        }
    }

    /// Runs the recovery that the user approved for `report`.
    public func recover(report: SystemRecoveryStatus, action: SystemRecoveryAction) async throws {
        guard let id = report.installationID, let der = report.certificateDER else {
            throw JerdError.unavailable("The recovery record cannot be read. An administrator must inspect it.")
        }
        let scope = try ConsentScope(
            certificate: InstallationCertificate(installationID: id, der: der),
            hostnames: report.previousHostnames + report.intendedHostnames, policies: Set(report.policies))
        let payload = try HelperWireProtocol.encode(SystemRecoveryApproval(recordID: report.id, action: action))
        try await withConsent(scope) {
            try await self.change { proxy, reply in proxy.recoverSetup(payload, reply: reply) }
        }
    }

    /// Opens `scope` (if any) for the duration of `body`, then closes it with its own token.
    private func withConsent(_ scope: ConsentScope?, _ body: () async throws -> Void) async throws {
        let token = try scope.map { try gate.open($0) }
        defer { token.map(gate.close) }
        try await body()
    }

    /// Sends a changing request without an app timeout. A nil error text means success.
    ///
    /// A transport failure is never retried here: the helper can have run the request before XPC
    /// refused its reply. Configure and remove read the status first, which restarts a stale helper.
    private func change(
        _ send: @escaping @Sendable (any JerdHelperProtocol, @escaping @Sendable (String?) -> Void) -> Void
    )
        async throws
    {
        try await waitForRunningRestart()
        do {
            let _: Bool = try await connection.call(timeout: nil) { proxy, gate in
                send(proxy) { error in
                    if let error {
                        gate.resolve(.failure(HelperWireError.error(from: error)))
                    } else {
                        gate.resolve(.success(true))
                    }
                }
            }
        } catch let failure as HelperTransportError {
            throw failure.userError
        }
    }
}
