import Darwin
import Foundation
import JerdFoundation

/// The private socket folder of one launch: `$TMPDIR/jerd-db-XXXXXXXX-X/` (mode 0700).
///
/// Socket paths must fit `sun_path` (104 bytes), so the folder is short and outside the data
/// folder. It is removed when its process stops.
enum DatabaseSocketFolder {
    /// The `sun_path` size, including the final NUL byte.
    static let socketPathLimit = 104
    /// Room for the longest socket name, for example `/.s.PGSQL.65535.lock`.
    static let socketNameRoom = 20

    /// Creates a new folder. It never reuses an existing path.
    static func create(in temporaryRoot: URL) throws -> URL {
        let folder = newPath(in: temporaryRoot)
        try create(at: folder)
        return folder
    }

    /// A new path. Nothing is created, so a caller can build a plan first and create the folder
    /// only when the plan needs it.
    static func newPath(in temporaryRoot: URL) -> URL {
        temporaryRoot.appendingPathComponent("jerd-db-" + UUID().uuidString.prefix(10), isDirectory: true)
    }

    /// Creates the folder at `folder` (mode 0700) when its socket paths fit `sun_path`. An
    /// existing item is never reused.
    static func create(at folder: URL) throws {
        guard folder.path.utf8.count + socketNameRoom < socketPathLimit, mkdir(folder.path, 0o700) == 0 else {
            throw DatabaseMessages.socketFolder
        }
    }
}
