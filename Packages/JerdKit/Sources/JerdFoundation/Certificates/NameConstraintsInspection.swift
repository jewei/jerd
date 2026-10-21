import Foundation

/// Tells whether a CA certificate is limited to `.test` names. The app uses it to find a CA that
/// needs the migration, and the helper uses it to refuse a new trust for an unconstrained CA.
public enum NameConstraintsInspection {
    /// What the name constraints of a CA allow.
    public enum Result: Equatable, Sendable {
        /// Exactly Jerd's critical constraints: `test` names only, and no IP address.
        case limitedToTest
        /// No name constraints, like the CA that Caddy made.
        case unconstrained
        /// Name constraints that are not Jerd's, or that are not critical.
        case otherConstraints
    }

    /// - Throws: `.invalid` when `certificate` is not a DER certificate, or when it repeats an
    ///   extension, which RFC 5280 forbids. Its constraints are then never trusted.
    public static func inspect(certificate: Data) throws -> Result {
        guard
            let fields = try CertificateExtensions.fields(
                of: CertificateObjectIdentifier.nameConstraints, in: certificate)
        else { return .unconstrained }
        guard fields.count == 3, fields[1] == DERElement(tag: 0x01, content: Data([0xFF])), fields[2].tag == 0x04
        else { return .otherConstraints }
        return fields[2].content == LocalRootTemplate.nameConstraintsValue ? .limitedToTest : .otherConstraints
    }
}
