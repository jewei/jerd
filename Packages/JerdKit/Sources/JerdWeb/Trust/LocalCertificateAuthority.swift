import Foundation
import JerdFoundation

/// The root certificate of a local CA: its PEM text, its DER bytes, and its SHA-256 fingerprint.
public struct LocalCertificateAuthority: Equatable, Sendable {
    /// The largest PEM or DER certificate that Jerd reads.
    public static let maximumCertificateBytes = 16_384
    /// The read limit of `root.crt`.
    public static let fileLimit = 65_536

    public let pem: Data
    public let der: Data

    /// Decodes one PEM certificate.
    /// - Throws: `.invalid` for a file of 16 KiB or more, text that is not UTF-8, or invalid PEM.
    public init(pem: Data) throws {
        guard pem.count < Self.maximumCertificateBytes, let text = String(data: pem, encoding: .utf8) else {
            throw JerdError.invalid("The Jerd CA certificate is invalid.")
        }
        let begin = "-----BEGIN CERTIFICATE-----"
        let end = "-----END CERTIFICATE-----"
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(begin), trimmed.hasSuffix(end), trimmed.count >= begin.count + end.count,
            let der = Data(
                base64Encoded: String(trimmed.dropFirst(begin.count).dropLast(end.count).filter { !$0.isWhitespace }))
        else { throw JerdError.invalid("The Jerd CA certificate is not valid PEM.") }
        self.pem = pem
        self.der = der
    }

    /// Reads `root.crt` strictly: a private regular file with one link, owned by the user.
    public static func read(_ file: URL) throws -> LocalCertificateAuthority {
        try LocalCertificateAuthority(pem: try AtomicFile.read(file, limit: fileLimit))
    }

    /// Lowercase hexadecimal SHA-256 of the DER bytes. The helper reports the same form.
    public var fingerprint: String { Self.fingerprint(of: der) }

    /// Lowercase hexadecimal SHA-256 of DER bytes.
    public static func fingerprint(of der: Data) -> String { FileDigest.hexSHA256(of: der) }
}
