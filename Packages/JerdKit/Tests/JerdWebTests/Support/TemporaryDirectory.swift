import Darwin
import Foundation

/// A private temporary folder for one test. The name can contain spaces and non-ASCII text.
///
/// The path is canonical (`/private/var/…` resolved the way `PathCanonicalizer` resolves it), so
/// tests can compare saved paths with it directly.
struct TemporaryDirectory {
    let url: URL

    init(_ suffix: String = "") throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jerd-tests-\(UUID().uuidString)\(suffix)")
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
    func file(_ relative: String, _ text: String = "") throws -> URL {
        let file = path(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        return file
    }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// The bytes of a file, or nil when it cannot be read.
func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// The text of a file, or "" when it cannot be read.
func text(_ url: URL) -> String { contents(url).map { String(decoding: $0, as: UTF8.self) } ?? "" }

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
