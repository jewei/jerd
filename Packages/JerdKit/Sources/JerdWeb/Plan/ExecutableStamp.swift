import Darwin
import Foundation
import JerdFoundation

/// The identity of an executable file on disk. A replaced or touched binary gets a new stamp.
///
/// It uses `stat` (links followed): device, inode, size, and the modification and change times
/// with nanoseconds.
public struct ExecutableStamp: Equatable, Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    let size: Int64
    let modified: [Int]
    let changed: [Int]

    /// - Throws: `.unavailable` when `path` is not an executable regular file.
    public init(path: String) throws {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG, access(path, X_OK) == 0 else {
            throw JerdError.unavailable("A selected runtime executable is unavailable: \(path)")
        }
        device = info.st_dev
        inode = info.st_ino
        size = info.st_size
        modified = [info.st_mtimespec.tv_sec, info.st_mtimespec.tv_nsec]
        changed = [info.st_ctimespec.tv_sec, info.st_ctimespec.tv_nsec]
    }

    /// The stamps of every path, keyed by path.
    public static func capture(_ paths: Set<String>) throws -> [String: ExecutableStamp] {
        var stamps: [String: ExecutableStamp] = [:]
        for path in paths.sorted() { stamps[path] = try ExecutableStamp(path: path) }
        return stamps
    }
}
