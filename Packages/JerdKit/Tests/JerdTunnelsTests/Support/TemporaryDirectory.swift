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

/// Checks `condition` again after each pause of 1 ms until it is true. There is no deadline, so a
/// slow machine cannot fail a test; the suite's `.timeLimit` only stops a test that hangs.
/// It returns when the test is cancelled. Use it only for a real child process, which has no
/// event to wait for.
func waitUntil(_ condition: () async throws -> Bool) async rethrows {
    while try await !condition() {
        do { try await Task.sleep(for: .milliseconds(1)) } catch { return }
    }
}
