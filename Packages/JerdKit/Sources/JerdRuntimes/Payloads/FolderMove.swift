import Darwin
import Foundation
import JerdFoundation

/// The final step of every installation: one atomic rename that never replaces an existing folder.
public enum FolderMove {
    /// Renames `source` to `target` on the same volume. Fails when `target` exists.
    /// - Throws: `.invalid` when the target exists (it is preserved), `.unavailable` for other errors.
    public static func withoutReplacing(_ source: URL, to target: URL) throws {
        try Task.checkCancellation()
        guard renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            if code == EEXIST {
                throw JerdError.invalid(
                    "The runtime folder \(target.lastPathComponent) already exists. It was preserved.")
            }
            throw JerdError.unavailable("Cannot install \(target.path) (\(SystemError.describe(code))).")
        }
    }
}
