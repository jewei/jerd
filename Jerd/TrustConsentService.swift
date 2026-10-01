import Foundation
import Security
import JerdCore

/// macOS trust consent must run in the logged-in app, where Security can display
/// authentication. The helper still imports/deletes the certificate and owns
/// the hosts/trust transaction. Only the active, approved CA can be changed.
final class TrustConsentService: NSObject, JerdTrustConsentProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var scope: TrustConsentScope?

    func authorize(installationID: UUID, certificateDER: Data, hostnames: Set<String>) throws {
        _ = try InstallationCertificate.validate(certificateDER, installationID: installationID)
        for hostname in hostnames { _ = try Hostname.validate(hostname) }
        lock.withLock { scope = TrustConsentScope(certificateDER: certificateDER, hostnames: hostnames, allowRemoval: true) }
    }

    func clear() { lock.withLock { scope = nil } }

    func changeTrust(_ request: Data, reply: @escaping @Sendable (Int32) -> Void) {
        guard request.count < 131_072, let change = try? JSONDecoder().decode(TrustConsentRequest.self, from: request),
              lock.withLock({ scope?.allows(change) == true }),
              let certificate = SecCertificateCreateWithData(nil, change.certificateDER as CFData) else {
            reply(errSecAuthFailed)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { @Sendable in
            if let hostnames = change.hostnames {
                let settings: [[String: Any]] = hostnames.map { hostname in [
                    kSecTrustSettingsPolicy as String: SecPolicyCreateSSL(true, nil),
                    kSecTrustSettingsPolicyString as String: hostname,
                    kSecTrustSettingsResult as String: NSNumber(value: SecTrustSettingsResult.trustRoot.rawValue)
                ] }
                reply(SecTrustSettingsSetTrustSettings(certificate, .admin, settings as CFArray))
            } else {
                let status = SecTrustSettingsRemoveTrustSettings(certificate, .admin)
                reply(status == errSecItemNotFound ? errSecSuccess : status)
            }
        }
    }
}
