import Foundation
import JerdFoundation
import JerdSystem
import Security

/// Adds and removes the Jerd CA in the system keychain, and asks the app for each trust change.
///
/// A keychain item that this call added is deleted again on any failure after the add, also when
/// the approval was interrupted (fixed problem 4). An item that existed before is never deleted here.
struct TrustInstaller: CertificateTrustChanging {
    let keychain: any KeychainCertificateStoring
    let inspector: any CertificateTrustInspecting
    /// Nil for a connection without consent; every change is then refused.
    let consent: (any ConsentRequesting)?

    func install(_ trust: CertificateTrust, replacingOwned: Bool) async throws {
        let consent = try requireConsent()
        let outcome = try keychain.add(trust.certificate.der)
        if outcome == .alreadyPresent, !replacingOwned {
            throw JerdError.invalid("This CA already exists outside Jerd's tracked setup. It was not changed.")
        }
        do {
            if replacingOwned, try inspector.isInstalled(trust) { return }
            let status = try await consent.change(trust.consentRequest)
            guard status == errSecSuccess else {
                throw JerdError.unavailable("Cannot set Jerd certificate trust: \(SecurityStatus.describe(status))")
            }
        } catch {
            guard outcome == .added else { throw error }
            do {
                try keychain.deleteExact(trust.certificate.der)
            } catch let cleanup {
                throw JerdError.partialChange(
                    "Certificate trust approval failed, and the Jerd certificate may remain in the system keychain. "
                        + cleanup.localizedDescription)
            }
            throw error
        }
    }

    func remove(_ certificate: InstallationCertificate) async throws {
        let consent = try requireConsent()
        let status = try await consent.change(.removal(of: certificate.der))
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw JerdError.unavailable("Cannot remove Jerd certificate trust: \(SecurityStatus.describe(status))")
        }
        try keychain.deleteExact(certificate.der)
    }

    private func requireConsent() throws -> any ConsentRequesting {
        guard let consent else { throw JerdError.unavailable("The app must approve certificate changes.") }
        return consent
    }
}
