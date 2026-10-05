/// A parsed v4 binary-document RSA/SHA-256 signature packet.
package struct OpenPGPSignature: Sendable, Equatable {
    /// The signed part of the packet body: version to the end of the hashed subpackets.
    package let signedHeader: [UInt8]
    /// The left 16 bits of the signed digest.
    package let hashPrefix: [UInt8]
    /// The RSA signature value, without leading zero octets.
    package let signatureMPI: [UInt8]
    /// The issuer fingerprint from the hashed area, in uppercase hexadecimal.
    package let issuerFingerprint: String

    package init(signedHeader: [UInt8], hashPrefix: [UInt8], signatureMPI: [UInt8], issuerFingerprint: String) {
        self.signedHeader = signedHeader
        self.hashPrefix = hashPrefix
        self.signatureMPI = signatureMPI
        self.issuerFingerprint = issuerFingerprint
    }
}
