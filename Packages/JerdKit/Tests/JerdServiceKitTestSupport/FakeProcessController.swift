import Darwin
import Foundation
import JerdProcess

/// A scripted process supervisor. It records every request and stop, and never starts a process.
package actor FakeProcessController: ProcessControlling {
    /// The end of a one-shot child, for example an initializer: it exits at once with `status`
    /// after it writes `output` to its log.
    package struct ScriptedExit: Sendable {
        package var status: Int32
        package var output: String

        package init(status: Int32, output: String = "") {
            self.status = status
            self.output = output
        }
    }

    /// Decides for each request if the child exits at once. Nil keeps the child running. The
    /// script can also act for the child, for example create its data folder.
    package typealias ExitScript = @Sendable (ProcessRequest) throws -> ScriptedExit?

    struct Child {
        let pid: pid_t
        let request: ProcessRequest
        var state: ProcessState
    }

    package private(set) var requests: [ProcessRequest] = []
    package private(set) var stopPolicies: [StopPolicy] = []
    private var children: [ProcessToken: Child] = [:]
    private var nextPID: pid_t = 60_000
    /// Outcomes for the next stops, in order. `.stopped` when empty.
    private var stopOutcomes: [StopOutcome] = []
    /// When false, a started child has no PID (the spawn produced no owned child).
    private var ownsNewChildren = true
    /// Text that each start writes to the log.
    private var logOutput = ""
    private var exitScript: ExitScript?
    private var heldStops: [CheckedContinuation<Void, Never>] = []
    private var holdingStops = false

    package init() {}

    package func start(_ request: ProcessRequest, log: ProcessLogFile) async throws -> ProcessToken {
        requests.append(request)
        let handle = try log.create()
        let exit = try exitScript?(request)
        handle.write(Data((exit?.output ?? logOutput).utf8))
        let token = ProcessToken()
        nextPID += 1
        let state: ProcessState = exit.map { .exited(status: $0.status) } ?? (ownsNewChildren ? .running : .notOwned)
        children[token] = Child(pid: nextPID, request: request, state: state)
        return token
    }

    package func state(of token: ProcessToken) -> ProcessState { children[token]?.state ?? .notOwned }

    package func processID(of token: ProcessToken) -> pid_t? {
        guard let child = children[token], child.state != .notOwned else { return nil }
        return child.pid
    }

    /// Answers at once: a running child counts as a timeout.
    package func waitForExit(of token: ProcessToken, timeout: Duration) async -> ProcessState { state(of: token) }

    package func stop(_ token: ProcessToken, policy: StopPolicy) async -> StopOutcome {
        stopPolicies.append(policy)
        if holdingStops { await withCheckedContinuation { heldStops.append($0) } }
        guard let child = children[token], child.state != .notOwned else {
            children[token] = nil
            return .notOwned
        }
        let outcome = stopOutcomes.isEmpty ? .stopped : stopOutcomes.removeFirst()
        if outcome != .timedOut(leaderRunning: true), outcome != .timedOut(leaderRunning: false) {
            children[token] = nil
        }
        return outcome
    }

    package func stopAll(policy: StopPolicy) async -> [ProcessToken: StopOutcome] {
        var outcomes: [ProcessToken: StopOutcome] = [:]
        for token in children.keys { outcomes[token] = await stop(token, policy: policy) }
        return outcomes
    }

    // MARK: Test controls

    /// The live (running) children.
    package var runningPIDs: [pid_t] { children.values.filter { $0.state == .running }.map(\.pid) }

    /// The running children with the requests that started them.
    package var runningChildren: [(pid: pid_t, request: ProcessRequest)] {
        children.values.filter { $0.state == .running }.map { ($0.pid, $0.request) }
    }

    /// The PID of the last started child.
    package var lastPID: pid_t? { requests.isEmpty ? nil : nextPID }

    /// Simulates that every running child exited with `status`.
    package func exitAll(status: Int32 = 1) {
        for (token, child) in children where child.state == .running {
            children[token]?.state = .exited(status: status)
        }
    }

    package func setStopOutcomes(_ outcomes: [StopOutcome]) { stopOutcomes = outcomes }

    package func setOwnsNewChildren(_ value: Bool) { ownsNewChildren = value }

    package func setLogOutput(_ text: String) { logOutput = text }

    package func setExitScript(_ script: ExitScript?) { exitScript = script }

    /// Makes later stops wait until `releaseStops()`.
    package func holdStops() { holdingStops = true }

    /// The number of stops that wait.
    package var heldStopCount: Int { heldStops.count }

    package func releaseStops() {
        holdingStops = false
        let waiting = heldStops
        heldStops = []
        for continuation in waiting { continuation.resume() }
    }
}
