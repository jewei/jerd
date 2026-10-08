import Foundation
import JerdFoundation
import JerdSystem
import JerdWeb

/// Pure mappings between the helper's wire values (JerdSystem) and the web layer's values
/// (JerdWeb). The two modules do not import each other, so JerdLive translates.
package enum HelperStatusMapping {
    /// The approved setup as the web layer sees it.
    ///
    /// A status that names a running helper transaction carries no setup at all. Reading it as
    /// "no setup" would ask for a new approval, and reading it as interrupted would offer a
    /// recovery of live work, so it throws: the caller retries after the transaction ends.
    /// A helper that waits for approval in Login Items & Extensions (turned off, or not yet allowed) also
    /// throws: its hosts and trust stay, so "approval required" would be wrong. A helper that was
    /// never registered is an empty setup, and the next Start asks for approval.
    package static func httpsStatus(_ status: HelperStatus) throws -> HTTPSSetupStatus {
        if status.availability == .requiresApproval { throw notAllowedError }
        let setup = status.setup
        if let operation = setup.operationInProgress {
            throw busyError(operation)
        }
        return HTTPSSetupStatus(
            hostnames: setup.hostnames, installationID: setup.installationID,
            certificateSHA256: setup.certificateSHA256, certificateDER: setup.certificateDER,
            hostsConfigured: setup.hostsConfigured, trustConfigured: setup.trustConfigured,
            trustPolicy: trustPolicy(setup.trustPolicy), hasPendingRecovery: setup.recovery != nil)
    }

    /// The interrupted transaction that waits for an approved recovery, or nil.
    /// - Throws: While a helper transaction runs, because it is not interrupted.
    package static func pendingRecovery(_ status: HelperStatus) throws -> SystemRecoveryStatus? {
        if let operation = status.setup.operationInProgress {
            throw busyError(operation)
        }
        return status.setup.recovery
    }

    package static func trustPolicy(_ policy: CertificateTrustPolicy) -> HTTPSTrustPolicy {
        switch policy {
        case .hostnames: .hostnames
        case .serverTLS: .serverTLS
        }
    }

    package static func certificatePolicy(_ policy: HTTPSTrustPolicy) -> CertificateTrustPolicy {
        switch policy {
        case .hostnames: .hostnames
        case .serverTLS: .serverTLS
        }
    }

    /// The validated arguments of `HelperClient.configure`. Invalid hostnames or a certificate that
    /// is not this installation's CA throw before the helper is called.
    package static func request(
        for registration: HTTPSRegistration
    ) throws -> (
        hostnames: ValidatedHostnames, certificate: JerdSystem.InstallationCertificate, policy: CertificateTrustPolicy
    ) {
        (
            try ValidatedHostnames(registration.hostnames),
            try JerdSystem.InstallationCertificate(
                installationID: registration.installationID, der: registration.certificateDER),
            certificatePolicy(registration.trustPolicy)
        )
    }

    static var notAllowedError: JerdError {
        JerdError.unavailable(
            "The Jerd helper is not allowed in Login Items & Extensions. Allow Jerd in System Settings → General → "
                + "Login Items & Extensions, then try again. Host entries and certificate settings stay."
        ).with(.openLoginItems)
    }

    static func busyError(_ operation: String) -> JerdError {
        JerdError.unavailable("The Jerd helper is running “\(operation)”. Wait until it finishes, then retry.")
    }
}
