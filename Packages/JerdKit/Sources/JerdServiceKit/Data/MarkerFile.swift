import Foundation
import JerdFoundation

/// Reads and writes small private JSON markers: identities, initialization markers, credentials,
/// and removed registrations. They use `JSONFileFormat.compact` (the old `JSONEncoder()` defaults).
public enum MarkerFile {
    /// The default read limit of a marker (64 KiB).
    public static let defaultLimit = 65_536

    /// Decodes a private marker of at most `limit` bytes.
    /// - Throws: `.corrupt` for an unreadable or undecodable marker, which stays in place.
    public static func read<Value: Decodable>(
        _ type: Value.Type, from file: URL, limit: Int = defaultLimit
    ) throws
        -> Value
    {
        do {
            return try JSONDecoder().decode(type, from: AtomicFile.read(file, limit: limit))
        } catch {
            throw JerdError.corrupt(
                "Cannot read \(file.lastPathComponent). The file was preserved. \(FailureDetail.describe(error))")
        }
    }

    /// Writes `value` atomically with mode 0600.
    public static func write<Value: Encodable>(_ value: Value, to file: URL) throws {
        try AtomicFile.write(JSONFileFormat.compact.makeEncoder().encode(value), to: file)
    }
}
