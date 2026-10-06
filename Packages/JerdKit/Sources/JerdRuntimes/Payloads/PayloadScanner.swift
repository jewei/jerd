import Darwin
import Foundation
import JerdFoundation
import JerdManifest

/// Lists and hashes every file of a payload folder, without following any link.
///
/// Hidden files count. A symbolic link, a FIFO, a device, or more than 50 000 files is refused.
/// Paths are built from directory entries, so every file stays inside the folder.
public enum PayloadScanner {
    /// The most files that a payload may have.
    public static let fileLimit = 50_000
    /// Finder writes this file when a user opens a folder. Verification of an installed folder ignores it.
    public static let finderMetadataName = FinderMetadata.name

    /// Hashes the files below `folder`.
    /// - Parameters:
    ///   - ignoring: top-level names to skip, for example the receipt file.
    ///   - ignoresFinderMetadata: skip `.DS_Store` files at any depth (verification of installed folders).
    public static func scan(
        _ folder: URL, ignoring: Set<String> = [], ignoresFinderMetadata: Bool = false
    ) throws -> [RelativePath: PayloadFileRecord] {
        var walk = Walk(ignoresFinderMetadata: ignoresFinderMetadata)
        try walk.visit(folder, path: [], ignoring: ignoring)
        guard !walk.files.isEmpty else { throw JerdError.invalid("The runtime package is empty.") }
        return walk.files
    }

    private struct Walk {
        let ignoresFinderMetadata: Bool
        var files: [RelativePath: PayloadFileRecord] = [:]

        mutating func visit(_ directory: URL, path: [String], ignoring: Set<String>) throws {
            let names: [String]
            do {
                names = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
            } catch {
                throw JerdError.invalid("The runtime files cannot be read.")
            }
            for name in names where !(path.isEmpty && ignoring.contains(name)) {
                if ignoresFinderMetadata, name == FinderMetadata.name { continue }
                try Task.checkCancellation()
                try visitEntry(directory.appendingPathComponent(name), path: path + [name])
            }
        }

        private mutating func visitEntry(_ url: URL, path: [String]) throws {
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw JerdError.invalid("The runtime files cannot be read.") }
            switch info.st_mode & S_IFMT {
            case S_IFLNK: throw JerdError.invalid("The prepared runtime contains a symbolic link.")
            case S_IFDIR: try visit(url, path: path, ignoring: [])
            case S_IFREG:
                guard files.count < PayloadScanner.fileLimit, let relative = RelativePath(path.joined(separator: "/"))
                else { throw JerdError.invalid("The prepared runtime has invalid or too many files.") }
                let executable = info.st_mode & S_IXUSR != 0
                files[relative] = PayloadFileRecord(sha256: try FileDigest.hexSHA256(of: url), executable: executable)
            default: throw JerdError.invalid("The prepared runtime has invalid or too many files.")
            }
        }
    }
}
