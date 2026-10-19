import CryptoKit
import Foundation
import JerdFoundation
import Security

/// Checks that the key of a CA that Jerd made is present and belongs to its certificate, so a
/// lost or damaged key gives a message that a user can act on, not a Caddy load error.
/// Both files stay in place.
package enum RootKeyCheck {
    /// The read limit of `root.key`; a P-256 PKCS#8 key in PEM has about 240 bytes.
    package static let fileLimit = 4_096

    package static func requireMatch(certificate: Data, keyFile: URL) throws {
        let problem = JerdError.corrupt(
            "The key of the Jerd CA is missing or does not belong to its certificate. The files were kept. "
                + "Remove System Setup in Advanced, then start the sites again to make a new CA.")
        guard let text = try? String(decoding: AtomicFile.read(keyFile, limit: fileLimit), as: UTF8.self),
            let key = try? P256.Signing.PrivateKey(pemRepresentation: text),
            let certificate = SecCertificateCreateWithData(nil, certificate as CFData),
            let publicKey = SecCertificateCopyKey(certificate),
            let bytes = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?,
            bytes == key.publicKey.x963Representation
        else { throw problem }
    }
}
