import Darwin
import Foundation
import Testing

/// A private temporary folder for one test. The name can contain spaces and non-ASCII text.
struct TemporaryDirectory {
    let url: URL

    init(_ suffix: String = "") throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("jerd-tests-\(UUID().uuidString)\(suffix)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        chmod(url.path, 0o700)
    }

    func path(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    /// Removes the folder after the guard against leaked fixtures: a process that still runs in the
    /// folder fails the test and is killed, so no fixture outlives the test run.
    func remove() {
        let survivors = FixtureReaper.reap(in: url)
        if !survivors.isEmpty {
            Issue.record("Fixture processes \(survivors) outlived their test. They were killed.")
        }
        try? FileManager.default.removeItem(at: url)
    }
}

/// The bytes of a file, or nil when it cannot be read.
func contents(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// The text of a file, or "" when it cannot be read.
func text(_ url: URL) -> String { contents(url).map { String(decoding: $0, as: UTF8.self) } ?? "" }

/// Creates an empty marker file that a fixture waits for.
func touch(_ url: URL) { FileManager.default.createFile(atPath: url.path, contents: Data()) }

/// Polls `condition` every 10 ms until it is true or the timeout passes. Returns the last result.
func eventually(timeout: Duration = .seconds(5), _ condition: () async throws -> Bool) async rethrows -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return try await condition()
}

/// Reads a PID that a fixture wrote as text, once the file exists.
func waitForPID(in file: URL) async -> pid_t? {
    _ = await eventually { pid_t(text(file).trimmingCharacters(in: .whitespacesAndNewlines)) != nil }
    return pid_t(text(file).trimmingCharacters(in: .whitespacesAndNewlines))
}

/// True when `kill(pid, 0)` proves that the process is gone.
func isGone(_ pid: pid_t) -> Bool { kill(pid, 0) == -1 && errno == ESRCH }
