import Darwin
import Foundation
import JerdFoundation

/// A private temporary folder for one test. The name contains a space to catch quoting mistakes.
struct TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-tunnels \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        chmod(url.path, 0o700)
    }

    /// The tunnel layout below this folder.
    var layout: TunnelsLayout { DataLayout(root: url).tunnels }

    func remove() { try? FileManager.default.removeItem(at: url) }
}

/// The bytes of a file, or nil when it cannot be read.
func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// The text of a file, or "" when it cannot be read.
func text(_ url: URL) -> String { contents(url).map { String(decoding: $0, as: UTF8.self) } ?? "" }

/// Polls `condition` every 2 ms until it is true or two seconds pass. Returns the last result.
/// It waits for work on other tasks to finish; it never decides a test by elapsed time.
func eventually(_ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return try await condition()
}
