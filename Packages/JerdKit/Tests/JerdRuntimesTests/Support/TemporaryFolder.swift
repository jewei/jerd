import Darwin
import Foundation
import JerdFoundation

/// A private temporary folder for one test.
struct TemporaryFolder {
    let url: URL

    init(_ suffix: String = "") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "jerd-runtime-tests-\(UUID().uuidString)\(suffix)")
        try OwnedDirectory.create(url)
    }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    /// Writes text to a relative path, creating parents, with the given mode.
    @discardableResult
    func write(_ text: String, to relative: String, mode: mode_t = 0o600) throws -> URL {
        let file = path(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
        chmod(file.path, mode)
        return file
    }

    /// Removes the folder, also when a test left a folder without permissions.
    func remove() {
        if let items = FileManager.default.enumerator(atPath: url.path) {
            for case let item as String in items { chmod(url.appendingPathComponent(item).path, 0o700) }
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// The permission bits of a path, without following a final link.
func permissions(_ url: URL) -> mode_t {
    var info = stat()
    lstat(url.path, &info)
    return info.st_mode & 0o777
}

/// A SHA-256 text made of one repeated hexadecimal digit.
func digest(_ character: Character) -> String { String(repeating: character, count: 64) }
