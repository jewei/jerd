import JerdFoundation
import JerdTestSupport

extension TemporaryDirectory {
    /// The tunnel layout below this folder.
    var layout: TunnelsLayout { DataLayout(root: url).tunnels }
}

/// Checks `condition` again after each pause of 1 ms until it is true. There is no deadline, so a
/// slow machine cannot fail a test; the suite's `.timeLimit` only stops a test that hangs.
/// It returns when the test is cancelled. Use it only for a real child process, which has no
/// event to wait for.
func waitUntil(_ condition: () async throws -> Bool) async rethrows {
    while try await !condition() {
        do { try await Task.sleep(for: .milliseconds(1)) } catch { return }
    }
}
