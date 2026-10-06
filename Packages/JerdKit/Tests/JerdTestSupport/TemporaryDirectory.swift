import Darwin
import Foundation
import Testing

/// A private temporary folder (mode 0700) for one test. The one copy for every test target.
///
/// The name is `jerd-tests-<UUID><suffix>`. Give a suffix with a space or non-ASCII text to
/// test quoting. The path is canonical (`/private/var/…`, resolved the way `PathCanonicalizer`
/// resolves saved paths), so tests can compare saved paths with it directly.
///
/// Remove the folder with `defer { folder.remove() }`, so that it goes away also when the test fails.
package struct TemporaryDirectory: Sendable {
    package let url: URL

    package init(_ suffix: String = "") throws {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jerd-tests-\(UUID().uuidString)\(suffix)", isDirectory: true)
        try FileManager.default.createDirectory(at: raw, withIntermediateDirectories: false)
        chmod(raw.path, 0o700)
        url = raw.standardizedFileURL.resolvingSymlinksInPath()
    }

    package func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    /// Creates a folder (and its parents) below the temporary folder.
    @discardableResult
    package func folder(_ relative: String) throws -> URL {
        let folder = path(relative)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes a file with `mode` below the temporary folder, and creates its parents.
    @discardableResult
    package func file(_ relative: String, _ data: Data, mode: mode_t = 0o600) throws -> URL {
        let file = path(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        chmod(file.path, mode)
        return file
    }

    @discardableResult
    package func file(_ relative: String, _ text: String = "", mode: mode_t = 0o600) throws -> URL {
        try file(relative, Data(text.utf8), mode: mode)
    }

    /// The names in the folder that start with `prefix`, sorted.
    package func names(withPrefix prefix: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).filter { $0.hasPrefix(prefix) }.sorted()
    }

    /// Removes the folder. First a fixture process that still runs in it fails the test and is
    /// killed, so no fixture outlives the test run. A folder that a test left without
    /// permissions gets them back, so that the removal can finish.
    package func remove() {
        let survivors = FixtureReaper.reap(in: url)
        if !survivors.isEmpty {
            Issue.record("Fixture processes \(survivors) outlived their test. They were killed.")
        }
        chmod(url.path, 0o700)
        if let items = FileManager.default.enumerator(atPath: url.path) {
            for case let item as String in items {
                let itemURL = url.appendingPathComponent(item)
                var info = stat()
                if lstat(itemURL.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR {
                    chmod(itemURL.path, 0o700)
                }
            }
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// The bytes of a file, or nil when it cannot be read.
package func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// The text of a file, or "" when it cannot be read.
package func text(_ url: URL) -> String { contents(url).map { String(decoding: $0, as: UTF8.self) } ?? "" }
