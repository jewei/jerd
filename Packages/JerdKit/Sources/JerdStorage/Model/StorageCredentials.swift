import JerdFoundation

/// The access key and secret key of the local S3 service, saved in `storage/credentials.json`.
///
/// `initialized.json` records the SHA-256 of the exact bytes of that file, so Jerd never encodes
/// it again (see `StoredCredentials`).
public struct StorageCredentials: Codable, Equatable, Sendable {
    public let accessKey: String
    public let secretKey: String

    public init(accessKey: String, secretKey: String) {
        self.accessKey = accessKey
        self.secretKey = secretKey
    }

    /// `JERD` and 16 uppercase hexadecimal characters (8 random bytes), and a secret key of 48
    /// uppercase hexadecimal characters (24 random bytes).
    public static func generate(using generator: SecretGenerator = .system) throws -> StorageCredentials {
        do {
            return StorageCredentials(
                accessKey: "JERD" + (try generator.hex(byteCount: 8, letterCase: .upper)),
                secretKey: try generator.hex(byteCount: 24, letterCase: .upper))
        } catch {
            throw StorageMessages.credentialsUnavailable
        }
    }

    /// Requires 20 characters `A-Z` or `0-9` for the access key and 48 characters `A-F` or `0-9`
    /// for the secret key.
    public func validate() throws {
        let access =
            accessKey.utf8.count == 20
            && accessKey.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) }
        guard access, HexEncoding.isHex(secretKey, length: 48, letterCase: .upper) else {
            throw StorageMessages.credentialsInvalid
        }
    }
}
