import Foundation
import JerdFoundation

/// Sums the logical sizes of the regular files in a folder, off the calling actor and cancellable.
public enum DirectorySize {
    /// The most entries one size check visits.
    public static let entryLimit = 1_000_000

    /// Symbolic links are counted as entries but never followed. An unreadable entry makes the
    /// whole check fail, so a size is never silently too small.
    /// - Throws: `.unavailable` for an unreadable tree or more than `entryLimit` entries, or
    ///   `CancellationError`.
    @concurrent
    public static func bytes(in root: URL, entryLimit: Int = entryLimit) async throws -> Int64 {
        try sum(root, entryLimit: entryLimit)
    }

    private static func sum(_ root: URL, entryLimit: Int) throws -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let failures = FailureFlag()
        let handler: (URL, any Error) -> Bool = { _, _ in
            failures.set()
            return true
        }
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: keys, options: [], errorHandler: handler)
        else { throw JerdError.unavailable("Cannot inspect the retained data folder.") }
        var size: Int64 = 0
        var count = 0
        while let file = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            count += 1
            guard count <= entryLimit else {
                throw JerdError.unavailable("This data folder is too large for a size check. Its files were preserved.")
            }
            let values = try file.resourceValues(forKeys: Set(keys))
            if values.isRegularFile == true, values.isSymbolicLink != true { size += Int64(values.fileSize ?? 0) }
        }
        guard !failures.isSet else {
            throw JerdError.unavailable("Some files in this folder cannot be read, so its size is unknown.")
        }
        return size
    }
}
