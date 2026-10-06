import Darwin
import Foundation
import JerdFoundation

/// Staged replacement under fixed names: write or link the stage, flush it, then `rename` it.
///
/// The stage names are fixed (`.zshrc.jerd-tmp`, `.JerdCLI-next`, `.php-next`), so a run after a
/// crash finds the leftovers of the earlier run and removes them before it stages again.
enum StagedFile {
    /// Creates `stage` exclusively with `mode`, writes `data`, and flushes it to the drive.
    static func write(_ data: Data, to stage: URL, mode: mode_t) throws {
        let descriptor = open(stage.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw failure(errno, "Cannot create \(stage.path)") }
        var complete = false
        defer {
            close(descriptor)
            if !complete { unlink(stage.path) }
        }
        let code = DescriptorIO.writeAll(data, to: descriptor)
        guard code == 0 else { throw failure(code, "Cannot write \(stage.path)") }
        guard fchmod(descriptor, mode) == 0, fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0 else {
            throw failure(errno, "Cannot save \(stage.path)")
        }
        complete = true
    }

    /// Creates the relative symbolic link `stage` → `destination`.
    static func link(_ stage: URL, to destination: String) throws {
        guard symlink(destination, stage.path) == 0 else { throw failure(errno, "Cannot create \(stage.path)") }
    }

    /// Replaces `target` with `stage` in one step.
    static func commit(_ stage: URL, to target: URL) throws {
        guard rename(stage.path, target.path) == 0 else {
            let code = errno
            unlink(stage.path)
            throw failure(code, "Cannot replace \(target.path)")
        }
    }

    /// Moves `stage` to `target` only when `target` does not exist (`RENAME_EXCL`), so a file
    /// that appears after the last check is never overwritten.
    /// - Throws: `.unavailable` when `target` exists or the rename fails; the stage is removed.
    static func commitNew(_ stage: URL, to target: URL) throws {
        guard renamex_np(stage.path, target.path, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            unlink(stage.path)
            if code == EEXIST {
                throw JerdError.unavailable("\(target.path) appeared during the setup. Set up the commands again.")
            }
            throw failure(code, "Cannot create \(target.path)")
        }
    }

    /// Removes the leftover stage of a crashed run: a file or a link. Anything else stays.
    static func removeLeftover(_ stage: URL) throws {
        if try checkLeftover(stage) { try AtomicFile.remove(stage) }
    }

    /// True when a leftover stage exists. Only a file or a link of the user can be a leftover.
    /// - Throws: `.invalid` for a folder or another item at the stage name.
    @discardableResult
    static func checkLeftover(_ stage: URL) throws -> Bool {
        var info = stat()
        guard lstat(stage.path, &info) == 0 else {
            let code = errno
            guard code == ENOENT else { throw failure(code, "Cannot inspect \(stage.path)") }
            return false
        }
        let type = info.st_mode & S_IFMT
        guard type == S_IFREG || type == S_IFLNK, info.st_uid == geteuid() else {
            throw JerdError.invalid("\(stage.path) is in the way of the setup. It was preserved. Remove it yourself.")
        }
        return true
    }

    /// `code` is read by the caller right after the failed call, before other work can change `errno`.
    private static func failure(_ code: Int32, _ action: String) -> JerdError {
        .unavailable("\(action) (\(SystemError.describe(code))).")
    }
}
