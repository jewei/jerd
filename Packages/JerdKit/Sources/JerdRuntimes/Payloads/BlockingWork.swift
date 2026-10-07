/// Runs long synchronous file work (hashing, copying, extraction) on a GCD thread, so it never
/// blocks a thread of the Swift concurrency pool.
///
/// The work runs as part of the calling task, on the serial queue of a `BlockingQueue`. So
/// `Task.isCancelled` and `Task.checkCancellation()` inside the work see the cancellation of that
/// task, and the per-chunk and per-entry checks of the file functions stop the work.
public enum BlockingWork {
    /// Runs `work` off the cooperative pool and returns its result.
    /// - Throws: `CancellationError` when the task is cancelled before the work starts, or while it
    ///   runs and the work checks for cancellation; any error of `work`.
    public static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await BlockingQueue().run(work)
    }
}
