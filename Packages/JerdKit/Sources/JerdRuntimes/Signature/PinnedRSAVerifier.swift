import Foundation
import JerdFoundation
import Security

/// Verifies a detached OpenPGP signature of a file with one pinned RSA publisher key.
///
/// Not checked (as before): signature creation and expiration time, key expiration or
/// revocation, and the issuer key ID subpacket. The pinned key and fingerprint replace them.
public struct PinnedRSAVerifier: Sendable {
    public let key: PinnedRSAKey

    public init(key: PinnedRSAKey) { self.key = key }

    /// Verifies `armoredSignature` over the bytes of `file`.
    ///
    /// - Throws: the key's single `.invalid` error for any signature problem. An unreadable file
    ///   throws the read error of `FileDigest`, and cancellation throws `CancellationError`.
    public func verify(file: URL, armoredSignature: Data) throws {
        let signature = try OpenPGPSignatureParser.parse(
            armored: armoredSignature, expectedFingerprint: key.fingerprint, rejecting: key.failure)
        let digest = try FileDigest.sha256(of: file, appending: OpenPGPTrailer.bytes(for: signature.signedHeader))
        try verify(digest: digest, signature: signature)
    }

    /// Checks the 16-bit prefix, then the RSA PKCS#1 v1.5 signature of the SHA-256 `digest`.
    package func verify(digest: Data, signature: OpenPGPSignature) throws {
        guard digest.count == 32, Array(digest.prefix(2)) == signature.hashPrefix,
            signature.issuerFingerprint == key.fingerprint, signature.signatureMPI.count <= key.modulusBytes,
            let publicKey = makePublicKey()
        else { throw key.failure }
        // An MPI drops leading zero octets. RSA needs the full modulus length.
        let padding = [UInt8](repeating: 0, count: key.modulusBytes - signature.signatureMPI.count)
        let value = Data(padding + signature.signatureMPI)
        guard
            SecKeyVerifySignature(
                publicKey, .rsaSignatureDigestPKCS1v15SHA256, digest as CFData, value as CFData, nil)
        else { throw key.failure }
    }

    private func makePublicKey() -> SecKey? {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        return SecKeyCreateWithData(key.publicKeyDER as CFData, attributes as CFDictionary, nil)
    }
}
