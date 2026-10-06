import Darwin
import Foundation
import JerdFoundation
import JerdServiceKit

/// The private socket folder of one launch: `$TMPDIR/jerd-db-XXXXXXXX-X/` (mode 0700).
///
/// Socket paths must fit `sun_path` (104 bytes), so the folder is short and outside the data
/// folder. It is removed when its process stops. Its `owner.json` names the instance folder, so
/// that `DatabaseSocketSweeper` can remove the folder of a run that ended without a stop.
enum DatabaseSocketFolder {
    /// The marker in each folder: `{"instance": "<absolute instance folder>"}`.
    struct Owner: Codable, Equatable, Sendable {
        let instance: String
    }

    /// The `sun_path` size, including the final NUL byte.
    static let socketPathLimit = 104
    /// Room for the longest socket name, for example `/.s.PGSQL.65535.lock`.
    static let socketNameRoom = 20
    /// The name prefix that the sweep looks for.
    static let prefix = "jerd-db-"
    static let ownerFileName = "owner.json"

    /// Creates a new folder for the instance folder `owner`. It never reuses an existing path.
    static func create(in temporaryRoot: URL, owner: URL) throws -> URL {
        let folder = newPath(in: temporaryRoot)
        try create(at: folder, owner: owner)
        return folder
    }

    /// A new path. Nothing is created, so a caller can build a plan first and create the folder
    /// only when the plan needs it.
    static func newPath(in temporaryRoot: URL) -> URL {
        temporaryRoot.appendingPathComponent(prefix + UUID().uuidString.prefix(10), isDirectory: true)
    }

    /// Creates the folder at `folder` (mode 0700) with its owner marker, when its socket paths
    /// fit `sun_path`. An existing item is never reused.
    static func create(at folder: URL, owner: URL) throws {
        guard folder.path.utf8.count + socketNameRoom < socketPathLimit, mkdir(folder.path, 0o700) == 0 else {
            throw DatabaseMessages.socketFolder
        }
        do {
            try MarkerFile.write(Owner(instance: owner.path), to: folder.appendingPathComponent(ownerFileName))
        } catch {
            // The folder is new and holds no socket yet. A failed removal leaves an empty
            // private folder without a marker, which no process uses.
            try? FileManager.default.removeItem(at: folder)
            throw DatabaseMessages.socketFolder
        }
    }
}
