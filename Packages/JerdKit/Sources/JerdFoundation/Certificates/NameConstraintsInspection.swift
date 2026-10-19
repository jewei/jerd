import Foundation

/// Tells whether a CA certificate is limited to `.test` names. The app uses it to find a CA that
/// needs the migration, and the helper uses it to refuse a new trust for an unconstrained CA.
public enum NameConstraintsInspection {
    public enum Result: Equatable, Sendable {
        /// Exactly Jerd's critical constraints: `test` names only, and no IP address.
        case limitedToTest
        /// No name constraints, like the CA that Caddy made.
        case unconstrained
        /// Name constraints that are not Jerd's, or that are not critical.
        case otherConstraints
    }

    /// - Throws: `.invalid` when `certificate` is not a DER certificate.
    public static func inspect(certificate: Data) throws -> Result {
        let identifier = try DERElement.single(
            in: DERWriter.objectIdentifier(CertificateObjectIdentifier.nameConstraints))
        for fields in try extensions(of: certificate) {
            guard let first = fields.first, first == identifier else { continue }
            guard fields.count == 3, fields[1] == DERElement(tag: 0x01, content: Data([0xFF])), fields[2].tag == 0x04
            else { return .otherConstraints }
            return fields[2].content == LocalRootTemplate.nameConstraintsValue ? .limitedToTest : .otherConstraints
        }
        return .unconstrained
    }

    /// The fields of each extension: the identifier, the optional critical flag, and the value.
    private static func extensions(of certificate: Data) throws -> [[DERElement]] {
        let invalid = JerdError.invalid("The CA is not a valid DER certificate.")
        let parts = try DERElement.single(in: certificate).children()
        guard parts.count == 3, parts[0].tag == 0x30 else { throw invalid }
        guard let wrapper = try parts[0].children().first(where: { $0.tag == 0xA3 }) else { return [] }
        let list = try wrapper.children()
        guard list.count == 1, list[0].tag == 0x30 else { throw invalid }
        return try list[0].children().map { try $0.children() }
    }
}
