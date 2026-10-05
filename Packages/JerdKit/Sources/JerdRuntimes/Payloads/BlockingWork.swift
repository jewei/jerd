import Dispatch

/// Runs long synchronous file work (hashing, copying, extraction) on a GCD thread, so it never
/// blocks a thread of the Swift concurrency pool (fixes P-B2).
public enum BlockingWork {
    /// Runs `work` off the cooperative pool and returns its result. A task cancelled before the
    /// work starts throws `CancellationError`.
    public static func run<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }
}
