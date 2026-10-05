import Foundation
import JerdFoundation
import Security

/// Reads the saved trust settings of a certificate from the user domain, then the admin domain.
public struct SystemTrustDecision: TrustDecisionPort {
    public init() {}

    /// The first domain with settings decides. User settings come first, so a user denial wins.
    public func isTrustedForServerTLS(_ der: Data) throws -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw JerdError.invalid("The local CA certificate is invalid.")
        }
        for domain in [SecTrustSettingsDomain.user, .admin] {
            var settings: CFArray?
            let status = SecTrustSettingsCopyTrustSettings(certificate, domain, &settings)
            if status == errSecItemNotFound { continue }
            guard status == errSecSuccess else {
                throw JerdError.unavailable("Cannot read the local CA trust settings (\(status)).")
            }
            guard let entries = settings as? [[String: Any]] else { return false }
            return TrustDecision.accepts(entries)
        }
        return false
    }
}
