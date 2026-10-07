/// The exit statuses of `jerd-snapshots`, the same as `./dev` (see AGENTS.md).
package enum SnapshotExitStatus: Int32, Sendable {
    case success = 0
    /// Rendering or writing failed, or the catalog is invalid.
    case failure = 1
    /// An argument or a page name is not valid.
    case usage = 2
}
