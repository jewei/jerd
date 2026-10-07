import Darwin
import Foundation
import JerdFoundation

/// Owns spawned children by token. Each child leads its own process group.
///
/// A leader that exits stays unreaped until a stop completes. This keeps its PID and group ID
/// reserved, so a group signal can never reach a process that Jerd did not start.
/// The `ceiling` is fixed at creation: the default `.graceful` supervisor never sends `SIGKILL`.
/// Stop every child before the supervisor is released; it does not stop them on its own.
public actor ProcessSupervisor: ProcessControlling {
    private struct Child {
        let pid: pid_t
        let log: ProcessLogFile
        let pipe: RedactingPipe?
        let descendants: TrackedDescendants
    }

    /// The strongest stop that this supervisor runs.
    public let ceiling: StopCeiling
    private let inspector: ProcessGroupInspector
    private let tree: ProcessTree
    private let trimmer: LogTrimScheduler
    private let groupPollInterval: Duration
    private var children: [ProcessToken: Child] = [:]
    private var stops: [ProcessToken: Task<StopOutcome, Never>] = [:]
    private var finished = FinishedStops()
    /// The number of stop engine runs. Concurrent stops of one token share one run.
    private(set) var engineRuns = 0

    /// - Parameter ceiling: `.graceful` (the default) never sends `SIGKILL`, whatever policy a
    ///   caller passes. Use `.forceful` only for processes that hold no user data.
    public init(
        ceiling: StopCeiling = .graceful, groupInspector: ProcessGroupInspector = ProcessGroupInspector(),
        processTree: ProcessTree = ProcessTree(), logTrimInterval: Duration = .seconds(1),
        groupPollInterval: Duration = .milliseconds(25)
    ) {
        self.ceiling = ceiling
        inspector = groupInspector
        tree = processTree
        trimmer = LogTrimScheduler(interval: logTrimInterval)
        self.groupPollInterval = groupPollInterval
    }

    public func start(_ request: ProcessRequest, log: ProcessLogFile) async throws -> ProcessToken {
        let plan = try SpawnPlan(request: request)
        try Spawner.requireSpawnable(plan, listeners: request.listeners)
        let handle = try log.create()
        let pipe =
            request.redactedValues.isEmpty
            ? nil : try RedactingPipe(log: handle.fileDescriptor, values: request.redactedValues)
        let pid: pid_t
        do {
            pid = try Spawner.spawn(plan, output: pipe?.writer ?? handle.fileDescriptor, listeners: request.listeners)
        } catch {
            await pipe?.finish()
            throw error
        }
        pipe?.closeParentWriter()
        let token = ProcessToken()
        children[token] = Child(pid: pid, log: log, pipe: pipe, descendants: TrackedDescendants())
        await trimmer.register(log)
        return token
    }

    public func state(of token: ProcessToken) -> ProcessState {
        guard let child = children[token] else { return .notOwned }
        return ChildStatus.peek(child.pid)
    }

    public func processID(of token: ProcessToken) -> pid_t? {
        guard let child = children[token], ChildStatus.peek(child.pid) != .notOwned else { return nil }
        return child.pid
    }

    public func waitForExit(of token: ProcessToken, timeout: Duration) async -> ProcessState {
        guard let child = children[token] else { return .notOwned }
        return await ExitWatcher.wait(for: child.pid, until: ContinuousClock.now + timeout)
    }

    /// Stops the group with `policy`, limited by `ceiling`.
    public func stop(_ token: ProcessToken, policy: StopPolicy) async -> StopOutcome {
        if let running = stops[token] { return await running.value }
        guard let child = children[token] else { return finished[token]?.outcome ?? .notOwned }
        let target = SupervisedGroup(
            leader: child.pid, inspector: inspector, tree: tree, descendants: child.descendants,
            pollInterval: groupPollInterval)
        let limited = ceiling.limit(policy)
        engineRuns += 1
        let task = Task {
            let outcome = await StopEngine.run(limited, on: target)
            await self.complete(token, outcome)
            return outcome
        }
        stops[token] = task
        return await task.value
    }

    public func stopAll(policy: StopPolicy) async -> [ProcessToken: StopOutcome] {
        await withTaskGroup(of: (ProcessToken, StopOutcome).self) { group in
            for token in children.keys {
                group.addTask { (token, await self.stop(token, policy: policy)) }
            }
            var outcomes: [ProcessToken: StopOutcome] = [:]
            for await (token, outcome) in group { outcomes[token] = outcome }
            return outcomes
        }
    }

    /// A problem with the log of `token`: a failed trim or a failed redacted write. Nil when none.
    /// After a completed stop it reports the final trim and the last write of the child.
    public func logProblem(of token: ProcessToken) async -> String? {
        guard let child = children[token] else { return finished[token]?.logProblem }
        if let failure = child.pipe?.writeFailure { return Self.writeProblem(failure) }
        return await trimmer.failure(for: child.log.url)
    }

    /// Gives up a child whose stop timed out: its log is closed and unregistered, and a detached
    /// watcher reaps the leader when it exits. The process itself keeps running.
    /// - Returns: the leader PID, for the user message, or nil when the token is unknown.
    func relinquish(_ token: ProcessToken) async -> pid_t? {
        guard stops[token] == nil, let child = children.removeValue(forKey: token) else { return nil }
        let outcome = StopOutcome.timedOut(leaderRunning: ChildStatus.peek(child.pid).isRunning)
        finished.record(token, .init(outcome: outcome, logProblem: nil))
        await child.pipe?.finish()
        _ = await trimmer.unregister(child.log)
        let pid = child.pid
        Task.detached(priority: .utility) {
            while await ExitWatcher.wait(for: pid, until: ContinuousClock.now + .seconds(3_600)) == .running {}
            ChildStatus.reap(pid)
        }
        return pid
    }

    /// Releases a child after its stop: reap and close on success, forget when not owned, keep on timeout.
    private func complete(_ token: ProcessToken, _ outcome: StopOutcome) async {
        stops[token] = nil
        if case .timedOut = outcome { return }
        guard let child = children.removeValue(forKey: token) else { return }
        if outcome == .stopped { ChildStatus.reap(child.pid) }
        finished.record(token, .init(outcome: outcome, logProblem: nil))
        await child.pipe?.finish()
        let writeFailure = child.pipe?.writeFailure.map(Self.writeProblem)
        let trimFailure = await trimmer.unregister(child.log)
        finished.record(token, .init(outcome: outcome, logProblem: writeFailure ?? trimFailure))
    }

    private static func writeProblem(_ failure: String) -> String {
        "The process log could not be written: \(failure)."
    }
}
