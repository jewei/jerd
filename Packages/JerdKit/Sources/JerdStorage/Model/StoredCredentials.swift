import Foundation
import JerdFoundation

/// The credentials with the exact bytes of `credentials.json` and their SHA-256.
///
/// Older builds wrote the file with a default `JSONEncoder`, whose key order is not fixed. The
/// hash in `initialized.json` covers those exact bytes, so the file is only ever written once,
/// by `create`, and read back as it is.
struct StoredCredentials: Equatable, Sendable {
    /// The largest credential file.
    static let sizeLimit = 65_535

    let credentials: StorageCredentials
    let bytes: Data

    /// The lowercase hexadecimal SHA-256 of `bytes`.
    var hash: String { FileDigest.hexSHA256(of: bytes) }

    /// Reads and validates `file`. It must be a private regular file below 64 KiB.
    /// - Throws: `.corrupt` for an invalid file, which stays in place.
    static func read(from file: URL) throws -> StoredCredentials {
        let bytes: Data
        do {
            bytes = try AtomicFile.read(file, limit: sizeLimit)
        } catch {
            throw StorageMessages.requiredFileInvalid
        }
        let credentials: StorageCredentials
        do {
            credentials = try JSONDecoder().decode(StorageCredentials.self, from: bytes)
        } catch {
            throw StorageMessages.credentialsInvalid
        }
        try credentials.validate()
        return StoredCredentials(credentials: credentials, bytes: bytes)
    }

    /// Generates new credentials and writes them once (mode 0600).
    static func create(at file: URL, using generator: SecretGenerator) throws -> StoredCredentials {
        let credentials = try StorageCredentials.generate(using: generator)
        let bytes = try JSONFileFormat.compact.makeEncoder().encode(credentials)
        try AtomicFile.write(bytes, to: file)
        return StoredCredentials(credentials: credentials, bytes: bytes)
    }
}
