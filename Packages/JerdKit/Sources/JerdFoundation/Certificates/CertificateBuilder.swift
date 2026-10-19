import CryptoKit
import Foundation

/// Builds and signs an X.509 v3 certificate with a P-256 key and ECDSA with SHA-256.
public struct CertificateBuilder: Sendable {
    /// One extension: its object identifier, the critical flag, and the DER of its value.
    public struct Extension: Sendable {
        public let identifier: [UInt64]
        public let isCritical: Bool
        public let value: Data

        public init(identifier: [UInt64], isCritical: Bool, value: Data) {
            self.identifier = identifier
            self.isCritical = isCritical
            self.value = value
        }

        var encoded: Data {
            DERWriter.sequence(
                [DERWriter.objectIdentifier(identifier)] + (isCritical ? [DERWriter.boolean(true)] : [])
                    + [DERWriter.octetString(value)])
        }
    }

    public var subjectCommonName: String
    public var issuerCommonName: String
    public var publicKey: P256.Signing.PublicKey
    /// Positive and at most 20 bytes, as RFC 5280 requires.
    public var serialNumber: Data
    public var notBefore: Date
    public var notAfter: Date
    public var extensions: [Extension]

    public init(
        subjectCommonName: String, issuerCommonName: String, publicKey: P256.Signing.PublicKey,
        serialNumber: Data, notBefore: Date, notAfter: Date, extensions: [Extension]
    ) {
        self.subjectCommonName = subjectCommonName
        self.issuerCommonName = issuerCommonName
        self.publicKey = publicKey
        self.serialNumber = serialNumber
        self.notBefore = notBefore
        self.notAfter = notAfter
        self.extensions = extensions
    }

    /// The DER of the certificate, signed by `issuerKey`.
    public func signed(by issuerKey: P256.Signing.PrivateKey) throws -> Data {
        let tbs = toBeSigned
        let signature = try issuerKey.signature(for: tbs)
        return DERWriter.sequence([tbs, Self.signatureAlgorithm, DERWriter.bitString(signature.derRepresentation)])
    }

    /// A random positive 16-byte serial number.
    public static func randomSerialNumber() -> Data {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        bytes[0] = (bytes[0] & 0x7F) | 0x01
        return Data(bytes)
    }

    /// The SHA-1 of the public key bits, the usual key identifier of RFC 5280 (4.2.1.2, method 1).
    public static func keyIdentifier(of key: P256.Signing.PublicKey) -> Data {
        Data(Insecure.SHA1.hash(data: key.x963Representation))
    }

    var toBeSigned: Data {
        DERWriter.sequence([
            DERWriter.contextSpecific(0, constructed: true, DERWriter.unsignedInteger(Data([2]))),
            DERWriter.unsignedInteger(serialNumber),
            Self.signatureAlgorithm,
            Self.name(issuerCommonName),
            DERWriter.sequence([DERWriter.time(notBefore), DERWriter.time(notAfter)]),
            Self.name(subjectCommonName),
            subjectPublicKeyInfo,
            DERWriter.contextSpecific(3, constructed: true, DERWriter.sequence(extensions.map(\.encoded))),
        ])
    }

    private var subjectPublicKeyInfo: Data {
        DERWriter.sequence([
            DERWriter.sequence([
                DERWriter.objectIdentifier(CertificateObjectIdentifier.ecPublicKey),
                DERWriter.objectIdentifier(CertificateObjectIdentifier.prime256v1),
            ]),
            DERWriter.bitString(publicKey.x963Representation),
        ])
    }

    private static var signatureAlgorithm: Data {
        DERWriter.sequence([DERWriter.objectIdentifier(CertificateObjectIdentifier.ecdsaWithSHA256)])
    }

    private static func name(_ commonName: String) -> Data {
        DERWriter.sequence([
            DERWriter.set([
                DERWriter.sequence([
                    DERWriter.objectIdentifier(CertificateObjectIdentifier.commonName),
                    DERWriter.utf8String(commonName),
                ])
            ])
        ])
    }
}
