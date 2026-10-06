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
        let (realRoot, components) = try containment(of: url, in: root)
        var current = realRoot
        var shown = root
        try requireOwnedDirectory(current, shown: shown, owner: owner)
        for component in components {
            current.appendPathComponent(component, isDirectory: true)
            shown.appendPathComponent(component, isDirectory: true)
            if FileProbe.presence(at: current) == .absent { try makeDirectory(current) }
            try requireOwnedDirectory(current, shown: shown, owner: owner)
        }
        try tighten(current, owner: owner)
    }

    /// Requires every component from `root` to `url` (both included) to be a real directory
    /// (not a symbolic link) owned by `owner`. Links above the root (such as `/tmp`) and a linked root
    /// itself are resolved; the components below the root are compared as written.
    public static func requireContained(_ url: URL, in root: URL, owner: uid_t = geteuid()) throws {
        let (realRoot, components) = try containment(of: url, in: root)
        var current = realRoot
        var shown = root
        try requireOwnedDirectory(current, shown: shown, owner: owner)
        for component in components {
            current.appendPathComponent(component, isDirectory: true)
            shown.appendPathComponent(component, isDirectory: true)
            try requireOwnedDirectory(current, shown: shown, owner: owner)
        }
    }

    /// The real path of `root` and the components of `url` below it.
    ///
    /// `standardizedFileURL` removes `/private` only from paths that exist, so it cannot compare a new
    /// folder with its root. Instead, the shortest prefix of `url` that is the root directory (same device
    /// and inode) marks the root; the components after it stay as written, so the caller still refuses
    /// a link among them.
    private static func containment(of url: URL, in root: URL) throws -> (root: URL, components: [String]) {
        guard let realRoot = realPath(of: root), let rootIdentity = identity(of: realRoot.path) else {
            throw invalidDirectory(root)
        }
        let target = lexicalComponents(of: url)
        for count in 0...target.count
        where identity(of: "/" + target.prefix(count).joined(separator: "/")) == rootIdentity {
            return (realRoot, Array(target.dropFirst(count)))
        }
        throw JerdError.invalid("The directory \(url.path) is outside Jerd's data folder.")
    }

    /// The path components after removing `.` and `..` lexically, as `standardizedFileURL` did.
    private static func lexicalComponents(of url: URL) -> [String] {
        var components: [String] = []
        for component in url.path.split(separator: "/") where component != "." {
            if component == ".." { _ = components.popLast() } else { components.append(String(component)) }
        }
        return components
    }

    /// The path with every link resolved, or nil when it does not exist.
    private static func realPath(of url: URL) -> URL? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return URL(filePath: String(cString: resolved), directoryHint: .isDirectory)
    }

    /// The device and inode of the item at `path` after links, or nil when it does not exist.
    private static func identity(of path: String) -> [UInt64]? {
        var info = stat()
        guard stat(path, &info) == 0 else { return nil }
        return [UInt64(UInt32(bitPattern: info.st_dev)), info.st_ino]
    }

    /// Checks the real path `url`; an error names `shown`, the same folder in the form that the caller used.
    private static func requireOwnedDirectory(_ url: URL, shown: URL, owner: uid_t) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR, info.st_uid == owner else {
            throw invalidDirectory(shown)
        }
    }

    private static func invalidDirectory(_ url: URL) -> JerdError {
        .invalid("The directory \(url.path) has an invalid type or owner. It was preserved.")
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
