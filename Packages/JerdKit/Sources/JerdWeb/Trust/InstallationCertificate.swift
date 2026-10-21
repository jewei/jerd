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
        // The DER check, not SecCertificateCopyValues: that call costs about 4 ms in each new
        // process, and the php launcher runs this check on every command.
        guard try BasicConstraintsInspection.isAuthority(certificate: der) else {
            throw JerdError.invalid("The certificate is not a certificate authority.")
        }
    }
}
