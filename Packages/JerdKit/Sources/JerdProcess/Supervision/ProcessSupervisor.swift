import Darwin
import Foundation
import JerdFoundation

/// Owns spawned children by token. Each child leads its own process group.
///
/// A leader that exits stays unreaped until a stop completes. This keeps its PID and group ID
/// reserved, so a group signal can never reach a process that Jerd did not start.
/// Stop every child before the supervisor is released; it does not stop them on its own.
public actor ProcessSupervisor: ProcessControlling {
    private struct Child {
        let pid: pid_t
        let log: ProcessLogFile
        let pipe: RedactingPipe?
    }

    private let inspector: ProcessGroupInspector
    private let trimmer: LogTrimScheduler
    private let groupPollInterval: Duration
    private var children: [ProcessToken: Child] = [:]
    private var stops: [ProcessToken: Task<StopOutcome, Never>] = [:]
    /// The final outcome of every completed stop, so a repeated stop gives the same answer.
    private var finished: [ProcessToken: StopOutcome] = [:]

    public init(
        groupInspector: ProcessGroupInspector = ProcessGroupInspector(), logTrimInterval: Duration = .seconds(1),
        groupPollInterval: Duration = .milliseconds(25)
    ) {
        inspector = groupInspector
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
            pipe?.finish()
            throw error
        }
        pipe?.closeParentWriter()
        let token = ProcessToken()
        children[token] = Child(pid: pid, log: log, pipe: pipe)
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

    public func stop(_ token: ProcessToken, policy: StopPolicy) async -> StopOutcome {
        if let running = stops[token] { return await running.value }
        guard let child = children[token] else { return finished[token] ?? .notOwned }
        let target = SupervisedGroup(leader: child.pid, inspector: inspector, pollInterval: groupPollInterval)
        let task = Task {
            let outcome = await StopEngine.run(policy, on: target)
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
    public func logProblem(of token: ProcessToken) async -> String? {
        guard let child = children[token] else { return nil }
        if let failure = child.pipe?.writeFailure { return "The process log could not be written: \(failure)." }
        return await trimmer.failure(for: child.log.url)
    }

    /// Releases a child after its stop: reap and close on success, forget when not owned, keep on timeout.
    private func complete(_ token: ProcessToken, _ outcome: StopOutcome) async {
        stops[token] = nil
        if case .timedOut = outcome { return }
        guard let child = children.removeValue(forKey: token) else { return }
        if outcome == .stopped { ChildStatus.reap(child.pid) }
        finished[token] = outcome
        child.pipe?.finish()
        await trimmer.unregister(child.log)
    }
}
