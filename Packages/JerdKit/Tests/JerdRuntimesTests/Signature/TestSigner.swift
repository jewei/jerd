import CryptoKit
import Foundation
import JerdRuntimes
import Security

/// An in-memory RSA-2048 publisher key that signs files as OpenPGP v4 detached signatures.
struct TestSigner {
    let privateKey: SecKey
    let pinnedKey: PinnedRSAKey

    init() throws {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2_048]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
            let publicKey = SecKeyCopyPublicKey(privateKey),
            let der = SecKeyCopyExternalRepresentation(publicKey, &error) as Data?
        else { throw SignerError.keyGeneration }
        self.privateKey = privateKey
        pinnedKey = PinnedRSAKey(
            fingerprint: SignaturePacketBuilder.testFingerprint, publicKeyDER: der, modulusBytes: 256,
            failureMessage: "The test publisher signature is invalid.")
    }

    /// Signs SHA-256(file || trailer). `adjust` can change the packet after signing.
    func sign(_ file: URL, adjust: (inout SignaturePacketBuilder) -> Void = { _ in }) throws -> Data {
        var builder = SignaturePacketBuilder()
        var hasher = SHA256()
        hasher.update(data: try Data(contentsOf: file))
        hasher.update(data: OpenPGPTrailer.bytes(for: builder.signedHeader))
        let digest = Data(hasher.finalize())
        var error: Unmanaged<CFError>?
        guard
            let signature = SecKeyCreateSignature(
                privateKey, .rsaSignatureDigestPKCS1v15SHA256, digest as CFData, &error) as Data?
        else { throw SignerError.signing }
        let value = Array(signature.drop { $0 == 0 })
        builder.hashPrefix = Array(digest.prefix(2))
        builder.value = value
        builder.bits = (value.count - 1) * 8 + (8 - (value.first ?? 0).leadingZeroBitCount)
        adjust(&builder)
        return builder.armored
    }

    /// A file with `data` in a new temporary folder.
    static func temporaryFile(_ data: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jerd-signature-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let file = folder.appendingPathComponent("archive.tar.gz")
        try data.write(to: file)
        return file
    }

    enum SignerError: Error {
        case keyGeneration
        case signing
    }
}
