import Darwin
import Foundation
import JerdFoundation

/// Checks of service data folders with `lstat`, without following a final symbolic link.
public enum DataFolder {
    /// True when `url` is a real directory (not a symbolic link).
    public static func isRealDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    /// True when `url` is a real regular file (not a symbolic link).
    public static func isRegularFile(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFREG
    }

    /// True when nothing is at `url`, or `url` is a real directory without entries.
    /// - Throws: when the folder cannot be listed. Safety checks must not guess.
    public static func isAbsentOrEmpty(_ url: URL) throws -> Bool {
        switch FileProbe.presence(at: url) {
        case .absent: return true
        case .unknown(let code):
            throw JerdError.unavailable("Cannot inspect \(url.path) (\(SystemError.describe(code))).")
        case .present:
            guard isRealDirectory(url) else { return false }
            return try FileManager.default.contentsOfDirectory(atPath: url.path).isEmpty
        }
    }
}
