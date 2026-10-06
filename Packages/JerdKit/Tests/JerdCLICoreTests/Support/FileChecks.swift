import Darwin
import Foundation

/// The permission bits of an item (not following a final link), or nil.
func mode(_ url: URL) -> Int? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return nil }
    return Int(info.st_mode & 0o7777)
}

/// The inode number of an item, to prove that a file was not rewritten.
func inode(_ url: URL) -> UInt64? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return nil }
    return info.st_ino
}

/// True when nothing exists at `url` (a broken link counts as something).
func isAbsent(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) != 0 && errno == ENOENT
}

/// The text of a symbolic link, or nil.
func linkText(_ url: URL) -> String? { try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) }
