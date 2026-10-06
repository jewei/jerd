import Darwin
import Foundation

/// A private temporary folder for one test. The name has a space and non-ASCII text on purpose.
struct TemporaryDirectory {
    let url: URL

    init(_ suffix: String = " mail ü") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-tests-\(UUID().uuidString)\(suffix)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        chmod(url.path, 0o700)
    }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// The bytes of a file, or nil when it cannot be read.
func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// The text of a file, or "" when it cannot be read.
func text(_ url: URL) -> String { contents(url).map { String(decoding: $0, as: UTF8.self) } ?? "" }

/// True when something (also a dangling link) is at `url`.
func exists(_ url: URL) -> Bool {
    var info = stat()
    return lstat(url.path, &info) == 0
}

/// Writes `text` to `url`, creating parent folders.
func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// The permission bits of a file or folder.
func mode(_ url: URL) -> mode_t {
    var info = stat()
    guard lstat(url.path, &info) == 0 else { return 0 }
    return info.st_mode & 0o777
}

/// Polls `condition` every 10 ms until it is true or the timeout passes. Returns the last result.
func eventually(timeout: Duration = .seconds(5), _ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return try await condition()
}

/// True when another open file description can take the lock at `url` now.
func isLockFree(_ url: URL) -> Bool {
    let descriptor = open(url.path, O_RDWR | O_CLOEXEC)
    guard descriptor >= 0 else { return true }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { return false }
    flock(descriptor, LOCK_UN)
    return true
}
