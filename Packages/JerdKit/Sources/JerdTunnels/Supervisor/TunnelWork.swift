import Foundation

/// The one task that works for one tunnel generation: the first launch, or the monitor loop.
///
/// The supervisor keeps at most one per tunnel and clears or replaces the slot only for the same
/// generation. Earlier builds cleared a shared slot after an `await`, so a late task could erase
/// the task of a newer Connect, and Stop could no longer cancel it (spec E 7.1.1).
struct TunnelWork: Sendable {
    let generation: TunnelGeneration
    let cancel: @Sendable () -> Void
    /// Waits until the task has finished.
    let finished: @Sendable () async -> Void

    init<Success: Sendable>(generation: TunnelGeneration, task: Task<Success, Never>) {
        self.generation = generation
        cancel = { task.cancel() }
        finished = { _ = await task.value }
    }
}
