import Foundation

/// The one task that works for one tunnel generation: the first launch, or the monitor loop.
/// `TunnelWorkSlots` keeps at most one per tunnel.
package struct TunnelWork: Sendable {
    package let generation: TunnelGeneration
    let cancel: @Sendable () -> Void
    /// Waits until the task has finished.
    let finished: @Sendable () async -> Void

    package init<Success: Sendable>(generation: TunnelGeneration, task: Task<Success, Never>) {
        self.generation = generation
        cancel = { task.cancel() }
        finished = { _ = await task.value }
    }
}
