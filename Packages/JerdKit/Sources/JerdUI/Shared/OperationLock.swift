import Observation

/// The one lock for work that changes the system or the shared configuration: site and HTTPS
/// setup changes, process recovery, backup deletion, PHP and Caddy registrations, the default
/// PHP, runtime activation, and the command-line tools. Only one such operation runs at a
/// time, as with the old global busy lock. The staged quit closes the lock first
/// and waits for the work that holds it (stage `siteWork`).
@MainActor
@Observable
public final class OperationLock {
    /// The work that holds the lock.
    public struct Work: Equatable, Sendable {
        /// What the work does, for example "Removing the selected backup…".
        public let message: String
        /// True when the quit may cancel the work instead of waiting for it.
        public let canCancel: Bool
    }

    /// The message when work cannot start because other work holds the lock.
    public static let busyMessage = "Wait for the current operation to finish."

    public private(set) var work: Work?
    /// True while a quit runs. No work starts then.
    public private(set) var isClosed = false
    @ObservationIgnored private var task: Task<Void, Never>?

    public init() {}

    /// True when new work can start now. Controls that start locked work use it.
    public var isFree: Bool { work == nil && !isClosed }

    /// Runs `body` while it holds the lock.
    /// - Returns: The task of the work, or nil when other work holds the lock or a quit runs;
    ///   `body` then does not run.
    @discardableResult
    public func run(
        _ message: String, canCancel: Bool = false, _ body: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never>? {
        guard isFree else { return nil }
        work = Work(message: message, canCancel: canCancel)
        let task = Task {
            await body()
            self.release()
        }
        self.task = task
        return task
    }

    /// Waits until the lock is free, then runs `body` while it holds the lock. Use it for work
    /// that must not fail only because other work runs, for example a runtime activation.
    /// - Throws: `CancellationError` when a quit closed the lock first; `body` then does not run.
    public func runWhenFree(_ message: String, _ body: @escaping @MainActor () async throws -> Void) async throws {
        while let current = task {
            await current.value
        }
        guard !isClosed else { throw CancellationError() }
        var failure: (any Error)?
        await run(message) {
            do { try await body() } catch { failure = error }
        }?.value
        if let failure { throw failure }
    }

    private func release() {
        work = nil
        task = nil
    }
}

extension OperationLock: ShutdownParticipant {
    public var shutdownPhase: ShutdownPhase { .siteWork }

    /// The work that the quit waits for, else the stage message.
    public var shutdownMessage: String {
        guard let work, !work.canCancel else { return ShutdownPhase.siteWork.message }
        return work.message
    }

    /// Closes the lock, cancels work that can stop, and waits for the work. Never fails: work
    /// that changes the system always finishes, so nothing is left half done.
    public func shutdown() async -> Bool {
        isClosed = true
        if work?.canCancel == true {
            task?.cancel()
        }
        while let current = task {
            await current.value
        }
        return true
    }

    public func resumeAfterCancelledQuit() {
        isClosed = false
    }
}
