/// Ends the helper process when it has nothing to do, so that launchd starts the current helper
/// file on the next connection. Before, a helper that ran before an app update kept the old code,
/// and the updated app refused it (code-signing requirement failure).
///
/// Idle means: no client connection, no listener lease, and no setup or recovery transaction.
/// The helper exits after `idleLimit` of idle checks in a row. When its own executable file was
/// replaced (an app update), it exits at the first idle check. It never exits while a lease or a
/// transaction is active, and a last check after `beginExit` keeps it running when work started.
struct IdleExitMonitor: Sendable {
    /// Thirty seconds: well above launchd's 10-second respawn throttle, so a helper that ends never
    /// delays the next on-demand start, and short enough that the next app start after a quit or an
    /// update meets a current helper.
    static let idleLimit: Duration = .seconds(30)
    /// The time between two idle checks.
    static let checkInterval: Duration = .seconds(5)

    let lifetime: HelperLifetime
    /// True while the service holds a listener lease or runs a transaction.
    let isBusy: @Sendable () async -> Bool
    /// True when the helper executable on disk is no longer the file that runs.
    let isReplaced: @Sendable () -> Bool
    let sleep: @Sendable (Duration) async throws -> Void
    /// Ends the process. Only called when the exit is decided.
    let exit: @Sendable () -> Void

    /// What the monitor remembers between two checks.
    struct Progress: Equatable, Sendable {
        var quiet: Duration = .zero
        var generation = 0
    }

    /// Checks every `checkInterval` until the helper exits or the task is cancelled.
    func run() async {
        var progress = Progress(generation: lifetime.snapshot.generation)
        while !Task.isCancelled {
            do { try await sleep(Self.checkInterval) } catch { return }
            if await check(&progress) {
                exit()
                return
            }
        }
    }

    /// One idle check after one `checkInterval`. Returns true when the helper must exit now; new
    /// connections are then refused.
    func check(_ progress: inout Progress) async -> Bool {
        let seen = lifetime.snapshot
        let busy = await isBusy()
        let idle = seen.connections == 0 && !busy && seen.generation == progress.generation
        progress.quiet = idle ? progress.quiet + Self.checkInterval : .zero
        progress.generation = seen.generation
        guard idle, progress.quiet >= Self.idleLimit || isReplaced() else { return false }
        guard lifetime.beginExit(expecting: seen.generation) else {
            progress.quiet = .zero
            return false
        }
        if await isBusy() {
            lifetime.cancelExit()
            progress.quiet = .zero
            return false
        }
        return true
    }
}
