import Foundation
import JerdFoundation

/// A private `.install-<UUID>` folder beside the final payload folders. The final rename stays on one volume.
public struct StagingFolder: Sendable {
    /// The name prefix of every staging folder. Listings skip hidden names.
    public static let prefix = ".install-"

    public let url: URL

    /// Creates a new staging folder (mode 0700) inside `directory`.
    public init(in directory: URL) throws {
        url = directory.appendingPathComponent("\(Self.prefix)\(UUID().uuidString)", isDirectory: true)
        try OwnedDirectory.create(url)
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

    /// Removes staging folders that a crash or a kill left behind (fixes P-I6).
    /// Call it only when no installation runs in `directory`.
    /// - Returns: the names that were removed.
    @discardableResult
    public static func removeAbandoned(in directory: URL) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names.filter { $0.hasPrefix(prefix) }.sorted().filter { name in
            let url = directory.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == geteuid() else {
                return false
            }
            return (try? FileManager.default.removeItem(at: url)) != nil
        }
    }
}
