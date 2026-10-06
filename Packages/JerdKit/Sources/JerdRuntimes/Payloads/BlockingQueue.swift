import Dispatch

/// An actor whose jobs run on its own GCD serial queue instead of the cooperative pool.
///
/// A call into the actor is a hop of the calling task, not a new task: the work keeps the
/// task's cancellation state, priority, and task-local values. A plain `DispatchQueue.async`
/// has no current task, so every cancellation check inside it would always pass.
actor BlockingQueue {
    private let queue = DispatchSerialQueue(label: "dev.jerd.runtimes.blocking-work", qos: .userInitiated)

    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    /// Runs `work` synchronously on the queue, inside the calling task.
    func run<T: Sendable>(_ work: @Sendable () throws -> T) throws -> T { try work() }
}
