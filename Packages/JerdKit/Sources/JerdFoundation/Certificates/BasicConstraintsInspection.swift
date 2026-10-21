import Foundation

/// Tells whether a certificate is a certificate authority, from its basic constraints.
public enum BasicConstraintsInspection {
    /// True only for basic constraints with `cA` TRUE (RFC 5280 4.2.1.9). A missing extension,
    /// the default FALSE, and every other form are false, so an unexpected form is never a CA.
    /// - Throws: `.invalid` when `certificate` is not a DER certificate or repeats an extension.
    public static func isAuthority(certificate: Data) throws -> Bool {
        guard
            let fields = try CertificateExtensions.fields(
                of: CertificateObjectIdentifier.basicConstraints, in: certificate),
            fields.count == 2 || (fields.count == 3 && fields[1].tag == 0x01),
            let value = fields.last, value.tag == 0x04
        else { return false }
        let constraints = try DERElement.single(in: value.content)
        guard constraints.tag == 0x30 else { return false }
        return try constraints.children().first == DERElement(tag: 0x01, content: Data([0xFF]))
    }
}
