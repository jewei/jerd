import Darwin
import Foundation
import JerdFoundation

/// An exclusive `flock` on a folder. The lock lives as long as this object.
///
/// The kernel releases the lock when the process ends, also after a crash or a kill. So a folder
/// that nobody holds is abandoned, and a folder that someone holds is in use, in any process (RT-7).
final class FolderLock: Sendable {
    /// The open folder that carries the lock. It is closed only in `deinit`.
    private let descriptor: Int32

    /// Locks `folder` without waiting.
    /// - Returns: nil when another holder has the lock, or when `folder` is not a real folder.
    init?(_ folder: URL) {
        let descriptor = open(folder.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0, Self.isStill(folder, open: descriptor) else {
            close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }

    /// True when the path still names the locked folder: a cleanup may remove a folder between
    /// its creation and its lock, and a lock on a removed folder protects nothing.
    private static func isStill(_ folder: URL, open descriptor: Int32) -> Bool {
        var opened = stat()
        var current = stat()
        guard fstat(descriptor, &opened) == 0, lstat(folder.path, &current) == 0 else { return false }
        return opened.st_dev == current.st_dev && opened.st_ino == current.st_ino
    }
}
