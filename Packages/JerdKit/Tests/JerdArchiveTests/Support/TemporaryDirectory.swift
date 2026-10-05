import Darwin
import Foundation

/// A private temporary folder for one test. The name can contain spaces and non-ASCII text.
struct TemporaryDirectory {
    let url: URL

    init(_ suffix: String = "") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-tests-\(UUID().uuidString)\(suffix)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    /// Removes the folder, also when a test left a folder without permissions.
    func remove() {
        if let items = FileManager.default.enumerator(atPath: url.path) {
            for case let item as String in items { chmod(url.appendingPathComponent(item).path, 0o700) }
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// The permission bits of a path, without following a final symbolic link.
func permissions(_ url: URL) -> mode_t {
    var info = stat()
    lstat(url.path, &info)
    return info.st_mode & 0o777
}

/// The bytes of a file, or nil when it cannot be read.
func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }
