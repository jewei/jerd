import Darwin
import Foundation
import JerdFoundation

/// The one rule for Finder's `.DS_Store` files in runtime folders (P-I7, RT-3).
///
/// Finder writes such a file when a user opens a folder. It is never part of a runtime: preparation
/// deletes it before the files are recorded, and every comparison skips it on both sides, so an
/// old receipt that records one still matches its folder.
package enum FinderMetadata {
    package static let name = ".DS_Store"

    /// True when the last component of `path` is `.DS_Store`.
    package static func contains(_ path: RelativePath) -> Bool { path.components.last == name }

    /// The records without Finder metadata.
    package static func removingMetadata<Value>(_ records: [RelativePath: Value]) -> [RelativePath: Value] {
        records.filter { !contains($0.key) }
    }

    /// Deletes every regular `.DS_Store` file below `folder`. Links are never followed; a link or
    /// another file type with that name stays, so that the permission step refuses it.
    package static func remove(in folder: URL) throws {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            throw JerdError.invalid("The runtime files cannot be read.")
        }
        for name in names {
            try Task.checkCancellation()
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw JerdError.invalid("The runtime files cannot be read.") }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: try remove(in: url)
            case S_IFREG where name == Self.name:
                guard unlink(url.path) == 0 else {
                    throw JerdError.unavailable("Cannot remove \(url.path) (\(SystemError.describe(errno))).")
                }
            default: continue
            }
        }
    }
}
