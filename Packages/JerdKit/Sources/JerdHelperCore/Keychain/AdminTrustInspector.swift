import Foundation
import JerdSystem
import Security

/// Reads the admin trust settings of the Jerd CA and compares them strictly with the setup.
/// It does not check that the CA is in the system keychain.
struct AdminTrustInspector: CertificateTrustInspecting {
    func isInstalled(_ trust: CertificateTrust) throws -> Bool {
        guard let certificate = trust.certificate.secCertificate else { return false }
        var settings: CFArray?
        let status = SecTrustSettingsCopyTrustSettings(certificate, .admin, &settings)
        if status == errSecItemNotFound { return false }
        try SecurityStatus.check(status, "read Jerd certificate trust")
        guard let entries = settings as? [[String: Any]] else { return false }
        return TrustSettingsPolicy.matches(entries, trust.scope)
    }
}
