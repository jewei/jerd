import Darwin
import Foundation
import JerdTestSupport

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
