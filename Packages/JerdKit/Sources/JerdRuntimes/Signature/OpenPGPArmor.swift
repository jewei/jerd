import Foundation
import JerdFoundation

/// Removes the ASCII armor of a detached signature (RFC 4880 §6.2) and returns the binary packet.
///
/// The CRC24 line is dropped and not checked: the RSA signature protects the content.
enum OpenPGPArmor {
    /// The largest armored signature that is read.
    static let sizeLimit = 16_384
    static let header = "-----BEGIN PGP SIGNATURE-----"
    static let footer = "-----END PGP SIGNATURE-----"

    static func decode(_ armored: Data, failure: JerdError) throws -> [UInt8] {
        guard armored.count <= sizeLimit, let text = String(data: armored, encoding: .utf8),
            text.hasPrefix(header), text.contains(footer)
        else { throw failure }
        // Armor headers contain ":", and the checksum line starts with "=".
        let body = text.components(separatedBy: .newlines)
            .filter { !$0.isEmpty && !$0.hasPrefix("-") && !$0.hasPrefix("=") && !$0.contains(":") }
            .joined()
        guard let binary = Data(base64Encoded: body), !binary.isEmpty else { throw failure }
        return Array(binary)
    }
}
