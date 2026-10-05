import CryptoKit
import Foundation
import JerdFoundation

/// Verifies a signed appcast and its update archives with the Ed25519 public key only.
///
/// This needs no private key and no Keychain, so CI and any Mac can check a release.
public struct AppcastVerifier: Sendable {
    private let key: Curve25519.Signing.PublicKey

    /// - Parameter publicKey: the 32 raw key bytes.
    public init(publicKey: Data) throws {
        do {
            key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        } catch {
            throw JerdError.invalid("The app update verification key is invalid.")
        }
    }

    /// The verifier of the official key.
    public static func official() throws -> AppcastVerifier {
        try AppcastVerifier(publicKey: AppUpdateSettings.official().publicKeyBytes)
    }

    /// Verifies the feed signature and then parses the signed content.
    /// - Throws: `.invalid` when the signature does not match or the content is not a valid appcast.
    public func verifiedAppcast(_ feed: Data) throws -> Appcast {
        let signed = try SignedFeed(feed)
        guard key.isValidSignature(signed.signature, for: signed.content) else {
            throw JerdError.invalid("The app update feed signature does not match the Jerd key.")
        }
        return try Appcast.parse(signed.content)
    }

    /// Verifies that `archive` has the enclosure length and signature.
    /// - Throws: `.invalid` for a different length or signature.
    public func verifyArchive(_ archive: URL, enclosure: AppcastEnclosure) throws {
        let data: Data
        do {
            data = try Data(contentsOf: archive, options: .alwaysMapped)
        } catch {
            throw JerdError.unavailable("Cannot read the update archive \(archive.path).")
        }
        guard Int64(data.count) == enclosure.length else {
            throw JerdError.invalid("The update archive does not have the length that the feed records.")
        }
        guard key.isValidSignature(enclosure.signature, for: data) else {
            throw JerdError.invalid("The update archive signature does not match the Jerd key.")
        }
    }
}
