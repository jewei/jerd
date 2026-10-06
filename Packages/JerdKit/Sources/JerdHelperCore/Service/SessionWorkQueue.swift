/// Runs the changing requests of one session one after another, in arrival order.
///
/// Earlier helpers started an unstructured task per message, so two messages of one connection
/// could run out of order (problem 20). Read-only status calls do not use this queue, so a status
/// call is never stuck behind an approval prompt.
final class SessionWorkQueue: Sendable {
    typealias Job = @Sendable () async -> Void

    private let jobs: AsyncStream<Job>.Continuation

    init() {
        let (stream, jobs) = AsyncStream<Job>.makeStream()
        self.jobs = jobs
        Task {
            for await job in stream { await job() }
        }
    }

    /// Adds `job`. Returns false after `finish()`; the job then never runs.
    @discardableResult func enqueue(_ job: @escaping Job) -> Bool {
        if case .terminated = jobs.yield(job) { return false }
        return true
    }

    /// Ends the queue after the jobs that are already in it.
    func finish() { jobs.finish() }
}
