import Darwin
import Foundation

/// A private temporary folder for one test. The name has a space and non-ASCII text on purpose.
package struct TemporaryDirectory {
    package let url: URL

    package init(_ suffix: String = " service kit ü") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-tests-\(UUID().uuidString)\(suffix)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        chmod(url.path, 0o700)
    }

    package func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    package func remove() { try? FileManager.default.removeItem(at: url) }
}

/// The bytes of a file, or nil when it cannot be read.
package func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// The text of a file, or "" when it cannot be read.
package func text(_ url: URL) -> String { contents(url).map { String(decoding: $0, as: UTF8.self) } ?? "" }

/// True when something (also a dangling link) is at `url`.
package func exists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
}

/// Writes `text` to `url`, creating parent folders.
package func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// The permission bits of a file or folder.
package func mode(_ url: URL) -> mode_t {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return 0 }
    return info.st_mode & 0o777
}

/// The inode of a file, or 0. An atomic write replaces the file, so a new inode proves a write.
package func inode(_ url: URL) -> UInt64 {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return 0 }
    return info.st_ino
}

/// Polls `condition` every 10 ms until it is true or the timeout passes. Returns the last result.
package func eventually(timeout: Duration = .seconds(5), _ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return try await condition()
}

/// True when another open file description can take the lock at `url` now.
package func isLockFree(_ url: URL) -> Bool {
    let descriptor = open(url.path, O_RDWR | O_CLOEXEC)
    guard descriptor >= 0 else { return true }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
    flock(descriptor, LOCK_UN)
    return true
}
