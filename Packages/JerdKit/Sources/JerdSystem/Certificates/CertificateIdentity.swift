import Foundation
import JerdFoundation
import Security

/// Pure checks of the installation CA: PEM decoding, the SHA-256 text, and the identity rule.
///
/// The identity rule is a consistency check, not a signature check: the common name must be
/// `Jerd Local CA <installation UUID>`, the certificate must be self-issued, and Basic Constraints
/// must mark it as a CA. The helper believes the installation ID that the signed app sends.
public enum CertificateIdentity {
    /// A certificate (PEM or DER) must be smaller than this (bytes).
    public static let maximumSize = 16_384

    /// The common name of the CA of `installationID` (uppercase UUID).
    public static func commonName(for installationID: UUID) -> String { "Jerd Local CA \(installationID.uuidString)" }

    /// Decodes one PEM certificate to DER. Text after the END marker is refused.
    public static func decodePEM(_ data: Data) throws -> Data {
        guard data.count < maximumSize, let pem = String(data: data, encoding: .utf8) else {
            throw JerdError.invalid("The Jerd CA certificate is invalid.")
        }
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        let trimmed = pem.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(begin), trimmed.hasSuffix(end), trimmed.count >= begin.count + end.count,
            let der = Data(
                base64Encoded: String(trimmed.dropFirst(begin.count).dropLast(end.count).filter { !$0.isWhitespace })),
            !der.isEmpty
        else { throw JerdError.invalid("The Jerd CA certificate is not valid PEM.") }
        return der
    }

    /// Lowercase hexadecimal SHA-256 of `data` (a certificate, a hosts file, or a journal).
    public static func sha256Hex(_ data: Data) -> String { FileDigest.hexSHA256(of: data) }

    /// Requires `der` to be the CA of `installationID` and returns it.
    public static func validateInstallationCA(_ der: Data, installationID: UUID) throws -> SecCertificate {
        guard der.count < maximumSize, let certificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw JerdError.invalid("The Jerd CA certificate is invalid.")
        }
        var name: CFString?
        guard SecCertificateCopyCommonName(certificate, &name) == errSecSuccess,
            name as String? == commonName(for: installationID), isSelfIssued(certificate)
        else { throw JerdError.invalid("Only this installation's Jerd root CA can be trusted.") }
        guard isCertificateAuthority(certificate) else {
            throw JerdError.invalid("The certificate is not a certificate authority.")
        }
        return certificate
    }

    /// Both normalized names must exist and be equal (fixed problem 19: two missing names do not match).
    private static func isSelfIssued(_ certificate: SecCertificate) -> Bool {
        guard let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate),
            let subject = SecCertificateCopyNormalizedSubjectSequence(certificate)
        else { return false }
        return issuer as Data == subject as Data
    }

    /// Security.framework gives the Basic Constraints label without localization.
    private static func isCertificateAuthority(_ certificate: SecCertificate) -> Bool {
        let values = SecCertificateCopyValues(certificate, [kSecOIDBasicConstraints] as CFArray, nil) as? [String: Any]
        let constraint = values?[kSecOIDBasicConstraints as String] as? [String: Any]
        let properties = constraint?[kSecPropertyKeyValue as String] as? [[String: Any]] ?? []
        return properties.contains { property in
            let value = property[kSecPropertyKeyValue as String]
            return property[kSecPropertyKeyLabel as String] as? String == "Certificate Authority"
                && (value as? String == "Yes" || (value as? NSNumber)?.boolValue == true)
        }
    }
}
