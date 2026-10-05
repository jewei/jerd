import Darwin
import Foundation

/// Durable whole-file replacement and bounded, owner-checked reads of private files.
///
/// A write never leaves a partial file at the target path: the bytes go to a temporary file
/// in the same folder (so the rename is atomic), the data is flushed, the temporary file
/// replaces the target with `rename`, and then the folder entry is flushed.
public enum AtomicFile {
    /// How much a write waits for the storage device before the rename.
    public enum Durability: Sendable, Equatable {
        /// `fsync`: the data reaches the drive, but the drive cache can still lose it on power loss.
        case standard
        /// `F_FULLFSYNC`: the drive also flushes its cache. Use for records that protect user data.
        case full
    }

    /// The mode of every file that this type creates.
    public static let fileMode: mode_t = 0o600

    /// Replaces `url` with `data` (mode 0600). The parent folder must exist.
    /// A symbolic link at `url` is replaced, never followed.
    public static func write(_ data: Data, to url: URL, durability: Durability = .full) throws {
        let folder = url.deletingLastPathComponent()
        let temporary = folder.appendingPathComponent(".\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, fileMode)
        guard descriptor >= 0 else {
            throw JerdError.unavailable(
                "Cannot create private file: \(temporary.path) (\(SystemError.describe(errno))).")
        }
        var renamed = false
        defer {
            close(descriptor)
            if !renamed { unlink(temporary.path) }
        }
        let writeError = DescriptorIO.writeAll(data, to: descriptor)
        guard writeError == 0 else {
            throw JerdError.unavailable("Cannot write \(url.path) (\(SystemError.describe(writeError))).")
        }
        guard flush(descriptor, durability), rename(temporary.path, url.path) == 0 else {
            throw JerdError.unavailable("Cannot save \(url.path) (\(SystemError.describe(errno))).")
        }
        renamed = true
        // The rename is complete. A failed folder flush cannot undo it, so it is not reported.
        let parent = open(folder.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        if parent >= 0 {
            _ = fsync(parent)
            close(parent)
        }
    }

    /// Reads a private file of at most `limit` bytes.
    ///
    /// The file must be a regular file with one link, owned by `owner`, and not a symbolic link.
    /// A FIFO or device is refused without blocking.
    public static func read(_ url: URL, limit: Int, owner: uid_t = geteuid()) throws -> Data {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            let code = errno
            if code == ELOOP { throw invalidFile(url) }
            throw JerdError.unavailable("Cannot read private file: \(url.path) (\(SystemError.describe(code))).")
        }
        defer { close(descriptor) }
        guard let info = DescriptorIO.status(of: descriptor), DescriptorIO.isPrivateRegularFile(info, owner: owner),
            info.st_size >= 0, info.st_size <= limit
        else { throw invalidFile(url) }
        switch DescriptorIO.read(from: descriptor, upTo: limit + 1) {
        case .success(let data):
            guard data.count <= limit else {
                throw JerdError.corrupt("The private file \(url.path) exceeds its size limit. It was preserved.")
            }
            return data
        case .failure(let failure):
            throw JerdError.unavailable(
                "Cannot read private file: \(url.path) (\(SystemError.describe(failure.code))).")
        }
    }

    /// Removes the file at `url` without following a symbolic link. An absent file is not an error.
    public static func remove(_ url: URL) throws {
        guard unlink(url.path) == 0 || errno == ENOENT else {
            throw JerdError.unavailable("Cannot remove \(url.path) (\(SystemError.describe(errno))).")
        }
    }

    private static func flush(_ descriptor: Int32, _ durability: Durability) -> Bool {
        switch durability {
        case .standard: fsync(descriptor) == 0
        // Some file systems do not support F_FULLFSYNC. fsync is then the strongest flush available.
        case .full: fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0
        }
    }

    private static func invalidFile(_ url: URL) -> JerdError {
        .corrupt("The private file \(url.path) has an invalid owner, type, or size. It was preserved.")
    }
}
