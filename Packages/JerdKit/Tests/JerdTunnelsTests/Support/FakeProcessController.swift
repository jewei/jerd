import Darwin
import Foundation
import JerdProcess

/// Pretends to start processes. It writes scripted output into the log and records every call.
actor FakeProcessController: ProcessControlling {
    private(set) var started: [ProcessRequest] = []
    private(set) var stopped: [ProcessToken] = []
    private var states: [ProcessToken: ProcessState] = [:]
    private var pids: [ProcessToken: pid_t] = [:]
    private var nextPID: pid_t = 50_000
    /// The output that each started process writes to its log.
    var output = ""
    /// False to simulate a child that something else reaped at once.
    var givesProcessID = true
    var stopOutcome: StopOutcome = .stopped

    func setOutput(_ value: String) { output = value }
    func setGivesProcessID(_ value: Bool) { givesProcessID = value }
    func setStopOutcome(_ value: StopOutcome) { stopOutcome = value }
    func exit(_ token: ProcessToken) { states[token] = .exited(status: 1) }

    func start(_ request: ProcessRequest, log: ProcessLogFile) throws -> ProcessToken {
        started.append(request)
        let handle = try log.create()
        try handle.write(contentsOf: Data(output.utf8))
        let token = ProcessToken()
        states[token] = .running
        pids[token] = nextPID
        nextPID += 1
        return token
    }

    func state(of token: ProcessToken) -> ProcessState { states[token] ?? .notOwned }

    func processID(of token: ProcessToken) -> pid_t? { givesProcessID ? pids[token] : nil }

    func waitForExit(of token: ProcessToken, timeout: Duration) -> ProcessState { state(of: token) }

    func stop(_ token: ProcessToken, policy: StopPolicy) -> StopOutcome {
        stopped.append(token)
        if case .timedOut = stopOutcome { return stopOutcome }
        states[token] = nil
        return stopOutcome
    }

    func stopAll(policy: StopPolicy) -> [ProcessToken: StopOutcome] {
        var outcomes: [ProcessToken: StopOutcome] = [:]
        for token in states.keys { outcomes[token] = stop(token, policy: policy) }
        return outcomes
    }
}
