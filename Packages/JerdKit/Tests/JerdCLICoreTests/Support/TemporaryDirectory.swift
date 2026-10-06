import Darwin
import Foundation

/// A private temporary folder for one test. The name contains a space and non-ASCII text.
///
/// The path is resolved the way `PathCanonicalizer` resolves saved project paths.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jerd-cli-tests café \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: false)
        chmod(raw.path, 0o700)
        url = raw.standardizedFileURL.resolvingSymlinksInPath()
    }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    /// Creates a folder (and its parents) below the temporary folder.
    @discardableResult
    func folder(_ relative: String) throws -> URL {
        let folder = path(relative)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a file below the temporary folder, creating its parents.
    @discardableResult
    func file(_ relative: String, _ data: Data, mode: Int16 = 0o600) throws -> URL {
        let file = path(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        chmod(file.path, mode_t(mode))
        return file
    }

    @discardableResult
    func file(_ relative: String, _ text: String, mode: Int16 = 0o600) throws -> URL {
        try file(relative, Data(text.utf8), mode: mode)
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// The bytes of a file, or nil when it cannot be read.
func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// The text of a file, or "" when it cannot be read.
func text(_ url: URL) -> String { contents(url).map { String(decoding: $0, as: UTF8.self) } ?? "" }

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
