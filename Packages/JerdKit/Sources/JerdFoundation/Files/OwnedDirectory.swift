import Darwin
import Foundation

/// Creates and checks private directories (mode 0700) that the current user owns.
///
/// It never changes the mode of a directory that belongs to another user, and it never
/// follows a symbolic link at a checked path.
public enum OwnedDirectory {
    /// The mode of every directory that this type creates or tightens.
    public static let mode: mode_t = 0o700

    /// Creates `url` and its missing parents with mode 0700.
    ///
    /// Existing parents are used as they are (for example `/var`, a link to `/private/var`).
    /// The final directory must be a real directory owned by `owner`; its mode is then set to 0700.
    public static func create(_ url: URL, owner: uid_t = geteuid()) throws {
        let target = url.standardizedFileURL
        var missing: [URL] = []
        var current = target
        while FileProbe.presence(at: current) == .absent, current.path != "/" {
            missing.append(current)
            current = current.deletingLastPathComponent()
        }
        for folder in missing.reversed() { try makeDirectory(folder) }
        try tighten(target, owner: owner)
    }

    /// Creates `url` below the owned directory `root`. Every component from `root` to `url`
    /// must be a real directory owned by `owner`; new components get mode 0700.
    public static func create(_ url: URL, within root: URL, owner: uid_t = geteuid()) throws {
        let components = try relativeComponents(of: url, in: root)
        var current = root.standardizedFileURL
        try requireOwnedDirectory(current, owner: owner)
        for component in components {
            current.appendPathComponent(component, isDirectory: true)
            if FileProbe.presence(at: current) == .absent { try makeDirectory(current) }
            try requireOwnedDirectory(current, owner: owner)
        }
        try tighten(current, owner: owner)
    }

    /// Requires every component from `root` to `url` (both included) to be a real directory
    /// (not a symbolic link) owned by `owner`. Paths are compared lexically after removing `.` and `..`.
    public static func requireContained(_ url: URL, in root: URL, owner: uid_t = geteuid()) throws {
        let components = try relativeComponents(of: url, in: root)
        var current = root.standardizedFileURL
        try requireOwnedDirectory(current, owner: owner)
        for component in components {
            current.appendPathComponent(component, isDirectory: true)
            try requireOwnedDirectory(current, owner: owner)
        }
    }

    private static func relativeComponents(of url: URL, in root: URL) throws -> [String] {
        let base = root.standardizedFileURL.pathComponents
        let target = url.standardizedFileURL.pathComponents
        guard target.starts(with: base) else {
            throw JerdError.invalid("The directory \(url.path) is outside Jerd's data folder.")
        }
        return Array(target.dropFirst(base.count))
    }

    private static func requireOwnedDirectory(_ url: URL, owner: uid_t) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == owner else {
            throw JerdError.invalid("The directory \(url.path) has an invalid type or owner. It was preserved.")
        }
    }

    private static func makeDirectory(_ url: URL) throws {
        guard mkdir(url.path, mode) == 0 || errno == EEXIST else {
            throw JerdError.unavailable("Cannot create the directory \(url.path) (\(SystemError.describe(errno))).")
        }
    }

    /// Checks and changes the mode through one descriptor, so a swapped-in link cannot redirect the change.
    private static func tighten(_ url: URL, owner: uid_t) throws {
        let descriptor = open(url.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw notOwned(url) }
        defer { close(descriptor) }
        guard let info = DescriptorIO.status(of: descriptor), info.st_mode & S_IFMT == S_IFDIR, info.st_uid == owner
        else { throw notOwned(url) }
        guard info.st_mode & 0o777 == mode || fchmod(descriptor, mode) == 0 else {
            throw JerdError.unavailable("Cannot protect the directory \(url.path) (\(SystemError.describe(errno))).")
        }
    }

    private static func notOwned(_ url: URL) -> JerdError {
        .invalid("Expected an app-owned directory: \(url.path)")
    }
}
