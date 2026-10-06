import Darwin
import Foundation
import JerdFoundation

/// A private `.install-<UUID>` folder beside the final payload folders. The final rename stays on one volume.
///
/// The folder is locked (`flock`) while any copy of this value lives, so `removeAbandoned(in:)`
/// never removes a folder that an installation in this or another process still uses.
public struct StagingFolder: Sendable {
    /// The name prefix of every staging folder. Listings skip hidden names.
    public static let prefix = ".install-"

    public let url: URL
    private let lock: FolderLock

    /// Creates and locks a new staging folder (mode 0700) inside `directory`.
    /// - Throws: `.unavailable` when the folder cannot be created or locked.
    public init(in directory: URL) throws {
        let url = directory.appendingPathComponent("\(Self.prefix)\(UUID().uuidString)", isDirectory: true)
        try OwnedDirectory.create(url)
        guard let lock = FolderLock(url) else {
            throw JerdError.unavailable("Cannot reserve the staging folder \(url.path). Try the installation again.")
        }
        self.url = url
        self.lock = lock
    }

    /// A child folder (mode 0700).
    public func folder(_ name: String) throws -> URL {
        let child = url.appendingPathComponent(name, isDirectory: true)
        try OwnedDirectory.create(child)
        return child
    }

    /// Removes the folder and its contents. Removal errors are ignored: a leftover is removed by
    /// `removeAbandoned(in:)` at the next start.
    public func remove() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Removes staging folders that a crash or a kill left behind.
    ///
    /// Only a real folder that the current user owns and that nobody holds locked is removed. A
    /// folder in use, a link, and a file with the prefix stay. Safe to call at any time.
    /// - Returns: the names that were removed.
    @discardableResult
    public static func removeAbandoned(in directory: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasPrefix(prefix) }.sorted().filter { name in
            let url = directory.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid(),
                let lock = FolderLock(url)
            else { return false }
            return withExtendedLifetime(lock) { (try? FileManager.default.removeItem(at: url)) != nil }
        }
    }
}
