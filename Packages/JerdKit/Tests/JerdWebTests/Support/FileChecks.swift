import Darwin
import Foundation

/// The POSIX mode bits of a file, or nil.
func mode(_ url: URL) -> Int? {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return nil }
    return Int(info.st_mode & 0o777)
}

/// True when nothing exists at `url` (a broken link counts as something).
func isAbsent(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) != 0 && errno == ENOENT
}
