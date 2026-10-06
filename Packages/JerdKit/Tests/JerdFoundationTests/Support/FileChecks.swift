import Darwin
import Foundation

/// The permission bits of a path, without following a final symbolic link.
func permissions(_ url: URL) -> mode_t {
    var info = stat()
    lstat(url.path, &info)
    return info.st_mode & 0o777
}
