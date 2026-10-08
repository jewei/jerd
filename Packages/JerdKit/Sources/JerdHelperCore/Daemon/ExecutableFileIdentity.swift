import Darwin

/// The device and inode of the helper executable at start. An app update replaces the bundle, so
/// the path then names another file (or none), while the process still runs the old one.
struct ExecutableFileIdentity: Equatable, Sendable {
    let path: String
    let device: dev_t
    let inode: ino_t

    /// The identity of the running executable, or nil when its path cannot be read.
    static func current() -> ExecutableFileIdentity? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getpid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return of(path)
    }

    /// The identity of the file at `path` now, or nil when it cannot be read.
    static func of(_ path: String) -> ExecutableFileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return ExecutableFileIdentity(path: path, device: info.st_dev, inode: info.st_ino)
    }

    /// True when the path now names another file, or no file. An unreadable path for another
    /// reason counts as unchanged, so the helper then waits for the normal idle limit.
    var isReplaced: Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return errno == ENOENT }
        return info.st_dev != device || info.st_ino != inode
    }
}
