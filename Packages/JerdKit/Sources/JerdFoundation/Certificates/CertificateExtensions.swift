import Foundation

/// Finds one extension of a DER certificate with the strict `DERElement` rules.
public enum CertificateExtensions {
    /// The fields of the extension `identifier`: the identifier, the optional critical flag, and
    /// the value. Nil when the certificate does not have the extension.
    /// - Throws: `.invalid` when `certificate` is not a DER certificate, or when it repeats an
    ///   extension, which RFC 5280 forbids.
    public static func fields(of identifier: [UInt64], in certificate: Data) throws -> [DERElement]? {
        let wanted = try DERElement.single(in: DERWriter.objectIdentifier(identifier))
        let all = try extensions(of: certificate)
        guard Set(all.map { $0[0] }).count == all.count else {
            throw JerdError.invalid("The CA repeats a certificate extension.")
        }
        return all.first { $0[0] == wanted }
    }

    /// The fields of each extension. Each extension is a SEQUENCE that starts with an object
    /// identifier.
    private static func extensions(of certificate: Data) throws -> [[DERElement]] {
        let invalid = JerdError.invalid("The CA is not a valid DER certificate.")
        let parts = try DERElement.single(in: certificate).children()
        guard parts.count == 3, parts[0].tag == 0x30 else { throw invalid }
        guard let wrapper = try parts[0].children().first(where: { $0.tag == 0xA3 }) else { return [] }
        let list = try wrapper.children()
        guard list.count == 1, list[0].tag == 0x30 else { throw invalid }
        return try list[0].children().map { entry in
            let fields = entry.tag == 0x30 ? try entry.children() : []
            guard let first = fields.first, first.tag == 0x06 else { throw invalid }
            return fields
        }
    }
}
