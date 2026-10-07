import Darwin
import Foundation
import JerdFoundation

/// A prepared payload has only private folders (0700), executables (0700), and other files (0600).
public enum PayloadPermissions {
    /// Sets the modes below `folder`. A file is executable when the user execute bit is set.
    /// - Throws: `.invalid` for a symbolic link or a file that is not regular.
    public static func apply(_ folder: URL) throws {
        try setMode(of: folder, 0o700)
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        } catch {
            throw JerdError.invalid("The runtime files cannot be read.")
        }
        for name in names {
            let url = folder.appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0 else { throw JerdError.invalid("The runtime files cannot be read.") }
            switch info.st_mode & S_IFMT {
            case S_IFLNK: throw JerdError.invalid("The prepared runtime contains a symbolic link.")
            case S_IFDIR: try apply(url)
            case S_IFREG: try setMode(of: url, info.st_mode & S_IXUSR != 0 ? 0o700 : 0o600)
            default: throw JerdError.invalid("The prepared runtime contains an invalid file.")
            }
        }
    }

    private static func setMode(of url: URL, _ mode: mode_t) throws {
        guard lchmod(url.path, mode) == 0 else {
            throw JerdError.unavailable("Cannot protect \(url.path) (\(SystemError.describe(errno))).")
        }
    }
}
