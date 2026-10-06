import CryptoKit
import Foundation
import JerdManifest

/// A test Ed25519 key that signs feeds and archives the way Sparkle's `sign_update` does, so tests can
/// check signed candidates without the real private key.
struct TestFeedKey {
    let key = Curve25519.Signing.PrivateKey()

    var verifier: AppcastVerifier {
        get throws { try AppcastVerifier(publicKey: key.publicKey.rawRepresentation) }
    }

    /// The base64 signature of `data`, as `sign_update -p` prints it.
    func signature(of data: Data) throws -> String {
        try key.signature(for: data).base64EncodedString()
    }

    /// `content` with Sparkle's signature block appended.
    func signedFeed(_ content: Data) throws -> Data {
        let block =
            "<!-- sparkle-signatures:\nedSignature: \(try signature(of: content))\nlength: \(content.count)\n-->\n"
        return content + Data(block.utf8)
    }
}
