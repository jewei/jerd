import Darwin
import Foundation
import JerdFoundation

extension ServiceDataCopier {
    /// Flushes `trees` and `folders` to the drive, so that a power loss cannot leave a journal
    /// that names an incomplete copy, or remove a journal before its restored copy is complete.
    ///
    /// Each regular file and folder below and including each tree gets `fsync`, then each of
    /// `folders` (the folders that hold the new entries). A last `F_FULLFSYNC` makes the drive
    /// write its cache, which holds every earlier write. The work runs off the calling actor.
    @concurrent
    static func flush(_ trees: [URL], folders: [URL]) async throws {
        for tree in trees {
            var pending = [tree]
            while let item = pending.popLast() {
                try Task.checkCancellation()
                if try sync(item) {
                    let names = try FileManager.default.contentsOfDirectory(atPath: item.path)
                    pending.append(contentsOf: names.map { item.appendingPathComponent($0) })
                }
            }
        }
        for folder in folders { _ = try sync(folder) }
        guard let last = folders.last ?? trees.last else { return }
        try sync(last, full: true)
    }

    /// Flushes one file or folder without following a link.
    /// - Returns: true when `item` is a folder.
    @discardableResult
    private static func sync(_ item: URL, full: Bool = false) throws -> Bool {
        var info = stat()
        guard lstat(item.path, &info) == 0 else { throw flushFailed(item, errno) }
        let isFolder = info.st_mode & S_IFMT == S_IFDIR
        guard isFolder || info.st_mode & S_IFMT == S_IFREG else { throw JerdError.invalid(notRegular) }
        let descriptor = open(item.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | (isFolder ? O_DIRECTORY : 0))
        guard descriptor >= 0 else { throw flushFailed(item, errno) }
        defer { close(descriptor) }
        // Some file systems do not support F_FULLFSYNC. fsync is then the strongest flush.
        let flushed = full ? fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0 : fsync(descriptor) == 0
        guard flushed else { throw flushFailed(item, errno) }
        return isFolder
    }

    private static func flushFailed(_ item: URL, _ code: Int32) -> JerdError {
        .unavailable(
            "Cannot write \(item.lastPathComponent) to disk (\(SystemError.describe(code))). The files were preserved.")
    }
}
