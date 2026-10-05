import Foundation
import JerdFoundation
import Security

/// The check that a certificate is this installation's own root CA, before Jerd asks to trust it.
public enum InstallationCertificate {
    /// Requires the common name `Jerd Local CA <installation UUID>`, a self-issued certificate,
    /// and the CA basic constraint.
    public static func validate(_ der: Data, installationID: UUID) throws {
        guard der.count < LocalCertificateAuthority.maximumCertificateBytes,
            let certificate = SecCertificateCreateWithData(nil, der as CFData)
        else { throw JerdError.invalid("The Jerd CA certificate is invalid.") }
        var commonName: CFString?
        guard SecCertificateCopyCommonName(certificate, &commonName) == errSecSuccess,
            commonName as String? == LocalAuthority.installation(installationID).name,
            let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate),
            let subject = SecCertificateCopyNormalizedSubjectSequence(certificate), issuer == subject
        else { throw JerdError.invalid("Only this installation's Jerd root CA can be trusted.") }
        guard isAuthority(certificate) else {
            throw JerdError.invalid("The certificate is not a certificate authority.")
        }
    }

    /// Security.framework reports the Basic Constraints with a non-localized label.
    private static func isAuthority(_ certificate: SecCertificate) -> Bool {
        let values = SecCertificateCopyValues(certificate, [kSecOIDBasicConstraints] as CFArray, nil) as? [String: Any]
        let constraint = values?[kSecOIDBasicConstraints as String] as? [String: Any]
        let properties = constraint?[kSecPropertyKeyValue as String] as? [[String: Any]] ?? []
        return properties.contains { property in
            guard property[kSecPropertyKeyLabel as String] as? String == "Certificate Authority" else { return false }
            let value = property[kSecPropertyKeyValue as String]
            return value as? String == "Yes" || (value as? NSNumber)?.boolValue == true
        }
    }
}
