import Darwin
import Foundation
import JerdFoundation

/// Copies service data trees for runtime update backups and restores.
///
/// Every node must be a real directory or a regular file. A copy is an APFS clone when the
/// volume supports it (fast, and no extra space until a side changes), else a full copy. The
/// work runs off the calling actor.
enum ServiceDataCopier {
    static let notRegular = "A service data file is not a regular file or directory. The update was stopped."

    /// Requires every node below and including `root` to be a real directory or a regular file.
    @concurrent
    static func validateTree(_ root: URL) async throws {
        var pending = [root]
        while let item = pending.popLast() {
            try Task.checkCancellation()
            var info = stat()
            guard lstat(item.path, &info) == 0 else { throw JerdError.invalid(notRegular) }
            switch info.st_mode & S_IFMT {
            case S_IFREG:
                continue
            case S_IFDIR:
                let names = try FileManager.default.contentsOfDirectory(atPath: item.path)
                pending.append(contentsOf: names.map { item.appendingPathComponent($0) })
            default:
                throw JerdError.invalid(notRegular)
            }
        }
    }

    /// Validates `source`, then clones it to the absent path `destination`, or copies it when
    /// the volume cannot clone.
    @concurrent
    static func copy(_ source: URL, to destination: URL) async throws {
        try await validateTree(source)
        try Task.checkCancellation()
        if clonefile(source.path, destination.path, UInt32(CLONE_NOFOLLOW)) == 0 { return }
        let cloneError = errno
        guard [ENOTSUP, EXDEV].contains(cloneError) else {
            throw JerdError.unavailable(
                "Cannot copy \(source.lastPathComponent) (\(SystemError.describe(cloneError))). The files were preserved."
            )
        }
        let flags = copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW | COPYFILE_EXCL)
        guard copyfile(source.path, destination.path, nil, flags) == 0 else {
            throw JerdError.unavailable(
                "Cannot copy \(source.lastPathComponent) (\(SystemError.describe(errno))). The files were preserved.")
        }
    }
}
