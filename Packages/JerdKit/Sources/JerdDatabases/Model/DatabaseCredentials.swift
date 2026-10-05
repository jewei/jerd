import Foundation
import JerdFoundation
import JerdServiceKit

/// The password of one instance, saved in `instances/<UUID>/credentials.json` as
/// `{"password": "<64 lowercase hex>"}`.
///
/// One password serves MySQL `root` and `jerd`, the PostgreSQL superuser `jerd`, and Redis `requirepass`.
public struct DatabaseCredentials: Codable, Equatable, Sendable {
    /// The largest credential file on read.
    public static let fileLimit = 4_096

    public let password: String

    public init(password: String) { self.password = password }

    /// 32 random bytes as 64 lowercase hexadecimal characters.
    public static func generate(using generator: SecretGenerator = .system) throws -> DatabaseCredentials {
        do {
            return DatabaseCredentials(password: try generator.hex(byteCount: 32))
        } catch {
            throw DatabaseMessages.credentialsUnavailable
        }
    }

    /// Requires exactly 64 lowercase hexadecimal characters.
    public func validate() throws {
        guard HexEncoding.isHex(password, length: 64) else { throw DatabaseMessages.credentialsInvalid }
    }

    /// Reads and validates a credential file.
    /// - Throws: `.corrupt` for an unreadable or invalid file, which stays in place.
    public static func read(from file: URL) throws -> DatabaseCredentials {
        let credentials: DatabaseCredentials
        do {
            credentials = try MarkerFile.read(DatabaseCredentials.self, from: file, limit: fileLimit)
        } catch {
            throw DatabaseMessages.credentialsInvalid
        }
        try credentials.validate()
        return credentials
    }

    /// Writes the credential file (mode 0600).
    public func write(to file: URL) throws {
        try validate()
        try MarkerFile.write(self, to: file)
    }
}
