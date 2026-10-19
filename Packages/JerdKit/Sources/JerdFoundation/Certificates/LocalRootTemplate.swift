import CryptoKit
import Foundation

/// The extensions and lifetime of Jerd's installation CA. The name constraints let the CA sign
/// only `.test` names and no IP address, so a stolen CA key cannot impersonate any other site.
public enum LocalRootTemplate {
    /// The one DNS subtree that the CA may sign: `test` and every name under it (RFC 5280 4.2.1.10).
    public static let permittedDNSName = "test"
    /// Ten years, like the root that Caddy made before.
    public static let lifetime: TimeInterval = 10 * 365 * 86_400

    /// The CA certificate, signed by its own key.
    public static func certificate(commonName: String, key: P256.Signing.PrivateKey, now: Date) throws -> Data {
        try builder(
            commonName: commonName, publicKey: key.publicKey, now: now, extensions: extensions(for: key.publicKey)
        )
        .signed(by: key)
    }

    /// Basic constraints (a CA), key usage (signs certificates and revocation lists), the key
    /// identifier, and the name constraints. All but the key identifier are critical.
    public static func extensions(for key: P256.Signing.PublicKey) -> [CertificateBuilder.Extension] {
        caExtensions(for: key) + [
            CertificateBuilder.Extension(
                identifier: CertificateObjectIdentifier.nameConstraints, isCritical: true, value: nameConstraintsValue)
        ]
    }

    /// The CA extensions without name constraints, the form of the CA that Caddy made.
    public static func caExtensions(for key: P256.Signing.PublicKey) -> [CertificateBuilder.Extension] {
        [
            CertificateBuilder.Extension(
                identifier: CertificateObjectIdentifier.basicConstraints, isCritical: true,
                value: DERWriter.sequence([DERWriter.boolean(true)])),
            // keyCertSign (bit 5) and cRLSign (bit 6): 0b0000_0110 with one unused bit.
            CertificateBuilder.Extension(
                identifier: CertificateObjectIdentifier.keyUsage, isCritical: true,
                value: DERWriter.bitString(Data([0x06]), unusedBits: 1)),
            CertificateBuilder.Extension(
                identifier: CertificateObjectIdentifier.subjectKeyIdentifier, isCritical: false,
                value: DERWriter.octetString(CertificateBuilder.keyIdentifier(of: key))),
        ]
    }

    /// Permitted: the DNS name `test`. Excluded: every IPv4 and every IPv6 address, because
    /// without an IP subtree, IP addresses are not limited at all.
    public static var nameConstraintsValue: Data {
        let permitted = DERWriter.sequence([
            DERWriter.contextSpecific(2, constructed: false, Data(permittedDNSName.utf8))
        ])
        let anyIPv4 = DERWriter.sequence([DERWriter.contextSpecific(7, constructed: false, Data(count: 8))])
        let anyIPv6 = DERWriter.sequence([DERWriter.contextSpecific(7, constructed: false, Data(count: 32))])
        return DERWriter.sequence([
            DERWriter.contextSpecific(0, constructed: true, permitted),
            DERWriter.contextSpecific(1, constructed: true, anyIPv4 + anyIPv6),
        ])
    }

    static func builder(
        commonName: String, publicKey: P256.Signing.PublicKey, now: Date, extensions: [CertificateBuilder.Extension]
    ) -> CertificateBuilder {
        CertificateBuilder(
            subjectCommonName: commonName, issuerCommonName: commonName, publicKey: publicKey,
            serialNumber: CertificateBuilder.randomSerialNumber(), notBefore: now.addingTimeInterval(-3_600),
            notAfter: now.addingTimeInterval(lifetime), extensions: extensions)
    }
}
