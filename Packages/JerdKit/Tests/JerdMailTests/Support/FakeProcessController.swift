import Darwin
import Foundation
import JerdProcess

/// A scripted process supervisor. It records every request and stop, and never starts a process.
actor FakeProcessController: ProcessControlling {
    struct Child {
        let pid: pid_t
        let request: ProcessRequest
        var state: ProcessState
    }

    private(set) var requests: [ProcessRequest] = []
    private(set) var stopPolicies: [StopPolicy] = []
    private var children: [ProcessToken: Child] = [:]
    private var nextPID: pid_t = 60_000
    /// Outcomes for the next stops, in order. `.stopped` when empty.
    var stopOutcomes: [StopOutcome] = []
    /// When false, a started child has no PID (the spawn produced no owned child).
    var ownsNewChildren = true
    /// Text that each start writes to the log.
    var logOutput = ""
    private var heldStops: [CheckedContinuation<Void, Never>] = []
    private var holdingStops = false

    func start(_ request: ProcessRequest, log: ProcessLogFile) async throws -> ProcessToken {
        requests.append(request)
        let handle = try log.create()
        handle.write(Data(logOutput.utf8))
        let token = ProcessToken()
        nextPID += 1
        children[token] = Child(pid: nextPID, request: request, state: ownsNewChildren ? .running : .notOwned)
        return token
    }

    func state(of token: ProcessToken) -> ProcessState { children[token]?.state ?? .notOwned }

    func processID(of token: ProcessToken) -> pid_t? {
        guard let child = children[token], child.state != .notOwned else { return nil }
        return child.pid
    }

    func waitForExit(of token: ProcessToken, timeout: Duration) async -> ProcessState { state(of: token) }

    func stop(_ token: ProcessToken, policy: StopPolicy) async -> StopOutcome {
        stopPolicies.append(policy)
        if holdingStops { await withCheckedContinuation { heldStops.append($0) } }
        guard children[token] != nil else { return .notOwned }
        let outcome = stopOutcomes.isEmpty ? .stopped : stopOutcomes.removeFirst()
        if outcome != .timedOut(leaderRunning: true), outcome != .timedOut(leaderRunning: false) {
            children[token] = nil
        }
        return outcome
    }

    func stopAll(policy: StopPolicy) async -> [ProcessToken: StopOutcome] {
        var outcomes: [ProcessToken: StopOutcome] = [:]
        for token in children.keys { outcomes[token] = await stop(token, policy: policy) }
        return outcomes
    }

    // MARK: Test controls

    /// The live (running) children.
    var runningPIDs: [pid_t] { children.values.filter { $0.state == .running }.map(\.pid) }

    /// The running children with the requests that started them.
    var runningChildren: [(pid: pid_t, request: ProcessRequest)] {
        children.values.filter { $0.state == .running }.map { ($0.pid, $0.request) }
    }

    /// The PID of the last started child.
    var lastPID: pid_t? { requests.isEmpty ? nil : nextPID }

    /// Simulates that every running child exited with `status`.
    func exitAll(status: Int32 = 1) {
        for (token, child) in children where child.state == .running {
            children[token]?.state = .exited(status: status)
        }
    }

    func setStopOutcomes(_ outcomes: [StopOutcome]) { stopOutcomes = outcomes }

    func setOwnsNewChildren(_ value: Bool) { ownsNewChildren = value }

    func setLogOutput(_ text: String) { logOutput = text }

    /// Makes later stops wait until `releaseStops()`.
    func holdStops() { holdingStops = true }

    /// The number of stops that wait.
    var heldStopCount: Int { heldStops.count }

    func releaseStops() {
        holdingStops = false
        let waiting = heldStops
        heldStops = []
        for continuation in waiting { continuation.resume() }
    }
}
