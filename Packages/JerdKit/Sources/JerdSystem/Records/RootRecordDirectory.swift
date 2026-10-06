import Darwin
import Foundation
import JerdFoundation

/// The one reader and writer of the helper record files in `/Library/Application Support/JerdHelper`.
///
/// The folder has mode 0700 and the expected owner (root in production). Files have mode 0600,
/// one link, and the expected owner; they are written atomically with a full flush. A file that
/// is a link, has another owner, or is above its limit is refused and preserved.
public struct RootRecordDirectory: Sendable {
    /// The record files and their size limits.
    public enum File: String, CaseIterable, Sendable {
        /// The committed registration.
        case registration = "registration.json"
        /// The journal of an unfinished transaction.
        case pending = "pending.json"
        /// The hosts bytes before the latest transaction (evidence only).
        case hostsBackup = "hosts.previous"
        /// The journal bytes from the start of the first recovery attempt of a transaction.
        case recoveryCopy = "recovery.previous.json"

        /// The largest accepted size (bytes).
        public var limit: Int {
            switch self {
            case .registration: 131_072
            case .pending, .recoveryCopy: 262_144
            case .hostsBackup: 1_048_576
            }
        }
    }

    public let url: URL
    public let owner: uid_t

    public init(url: URL, owner: uid_t) {
        self.url = url
        self.owner = owner
    }

    public func location(of file: File) -> URL { url.appendingPathComponent(file.rawValue) }

    /// True unless `lstat` proves that the file is absent. An unknown state counts as present.
    public func exists(_ file: File) -> Bool { FileProbe.presence(at: location(of: file)).mayExist }

    /// The bytes of `file`, or nil when it is proven absent.
    public func read(_ file: File) throws -> Data? {
        guard FileProbe.presence(at: location(of: file)) != .absent else { return nil }
        return try AtomicFile.read(location(of: file), limit: file.limit, owner: owner)
    }

    /// Creates the folder (mode 0700) when needed and requires the expected owner.
    public func prepare() throws {
        do {
            try OwnedDirectory.create(url, owner: owner)
        } catch let error as JerdError where error.kind == .invalid {
            throw JerdError.invalid("The helper data directory has an invalid owner.")
        }
    }

    public func write(_ data: Data, to file: File) throws {
        guard data.count <= file.limit else {
            throw JerdError.invalid(
                "The helper record \(file.rawValue) would exceed its size limit. It was not written.")
        }
        try prepare()
        try AtomicFile.write(data, to: location(of: file), durability: .full)
    }

    /// Removes `file`. An absent file is not an error.
    public func remove(_ file: File) throws {
        try AtomicFile.remove(location(of: file))
    }
}
