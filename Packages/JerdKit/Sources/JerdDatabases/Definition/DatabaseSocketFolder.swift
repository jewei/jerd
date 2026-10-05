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
        let name = "jerd-db-" + UUID().uuidString.prefix(10)
        let folder = temporaryRoot.appendingPathComponent(name, isDirectory: true)
        guard folder.path.utf8.count + socketNameRoom < socketPathLimit, mkdir(folder.path, 0o700) == 0 else {
            throw DatabaseMessages.socketFolder
        }
        return folder
    }
}
