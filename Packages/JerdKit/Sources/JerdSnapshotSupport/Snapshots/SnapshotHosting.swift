/// The effects of `SnapshotCommand` on its process, so tests can run the command without
/// changing the settings of the test process.
@MainActor
package protocol SnapshotHosting {
    /// Fixes the settings that change drawing. It must run before AppKit starts.
    func prepareProcess(contrast: SnapshotContrast)

    /// Runs `jerd-snapshots` again in a new process with `arguments`. Returns its exit status.
    func runContrastPass(arguments: [String]) -> Int32

    /// Writes one line to standard output.
    func write(_ line: String)

    /// Writes one line to standard error.
    func writeError(_ line: String)
}
