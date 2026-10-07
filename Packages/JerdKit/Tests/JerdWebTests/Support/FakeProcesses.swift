import Darwin
import Foundation
import JerdFoundation
import JerdProcess
import os

/// A process supervisor that starts nothing. FPM masters bind their pool socket, so socket waits
/// and pings work; tests can fail a launch, crash a process, or silence the pings.
actor FakeProcesses: ProcessControlling {
    struct Child {
        let request: ProcessRequest
        let pid: pid_t
        var state: ProcessState = .running
        var socket: (descriptor: Int32, path: String)?
    }

    /// PIDs of fake children that still run, read by the fake process observer.
    nonisolated let live = OSAllocatedUnfairLock<Set<pid_t>>(initialState: [])
    private(set) var children: [ProcessToken: Child] = [:]
    private(set) var order: [ProcessToken] = []
    private(set) var stops: [(ProcessToken, Int32)] = []
    private var waiters: [ProcessToken: [UUID: CheckedContinuation<ProcessState, Never>]] = [:]
    private var nextPID: pid_t = 50_000
    /// Markers (see `crash(where:)`) of processes whose stop times out and leaves them running.
    private var surviving: Set<String> = []
    private let failLaunch: @Sendable (ProcessRequest) -> Bool
    private let bindSockets: Bool

    init(failLaunch: @escaping @Sendable (ProcessRequest) -> Bool = { _ in false }, bindSockets: Bool = true) {
        self.failLaunch = failLaunch
        self.bindSockets = bindSockets
    }

    var startCount: Int { order.count }
    var requests: [ProcessRequest] { order.compactMap { children[$0]?.request } }
    var allStopped: Bool { children.values.allSatisfy { $0.state != .running } }

    func start(_ request: ProcessRequest, log: ProcessLogFile) async throws -> ProcessToken {
        _ = try log.create()
        if failLaunch(request) { throw JerdError.processFailed("Injected launch failure") }
        let token = ProcessToken()
        nextPID += 1
        var child = Child(request: request, pid: nextPID)
        if bindSockets, request.arguments.last == "-F" { child.socket = try Self.bindPoolSocket(request) }
        children[token] = child
        order.append(token)
        let pid = child.pid
        live.withLock { _ = $0.insert(pid) }
        return token
    }

    func state(of token: ProcessToken) -> ProcessState { children[token]?.state ?? .notOwned }

    func processID(of token: ProcessToken) -> pid_t? { children[token]?.pid }

    func waitForExit(of token: ProcessToken, timeout: Duration) async -> ProcessState {
        guard let child = children[token], child.state == .running else { return state(of: token) }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { waiters[token, default: [:]][id] = $0 }
        } onCancel: {
            Task { await self.resumeWaiter(token, id) }
        }
    }

    func stop(_ token: ProcessToken, policy: StopPolicy) async -> StopOutcome {
        guard let child = children[token] else { return .notOwned }
        stops.append((token, policy.signal))
        if child.state == .running, Self.matches(child.request, any: surviving) {
            return .timedOut(leaderRunning: true)
        }
        end(token, .signalled(signal: policy.signal))
        return .stopped
    }

    func stopAll(policy: StopPolicy) async -> [ProcessToken: StopOutcome] {
        var outcomes: [ProcessToken: StopOutcome] = [:]
        for token in order { outcomes[token] = await stop(token, policy: policy) }
        return outcomes
    }

    /// Ends the process with `arguments.last == marker` (for example "-F" or "run") as an exit.
    func crash(where marker: String) {
        for token in order
        where children[token]?.request.arguments.last == marker
            || children[token]?.request.arguments.first == marker
        {
            end(token, .exited(status: 1))
        }
    }

    /// The stop of the process with `marker` times out and leaves it running, until `survive(nil)`.
    func survive(where marker: String?) {
        surviving = marker.map { [$0] } ?? []
    }

    private static func matches(_ request: ProcessRequest, any markers: Set<String>) -> Bool {
        markers.contains { request.arguments.last == $0 || request.arguments.first == $0 }
    }

    /// The signals of every stop, in order.
    var stopSignals: [Int32] { stops.map(\.1) }

    private func end(_ token: ProcessToken, _ state: ProcessState) {
        guard var child = children[token], child.state == .running else { return }
        child.state = state
        if let socket = child.socket {
            close(socket.descriptor)
            unlink(socket.path)
            child.socket = nil
        }
        children[token] = child
        let pid = child.pid
        live.withLock { _ = $0.remove(pid) }
        for waiter in (waiters.removeValue(forKey: token) ?? [:]).values { waiter.resume(returning: state) }
    }

    private func resumeWaiter(_ token: ProcessToken, _ id: UUID) {
        waiters[token]?.removeValue(forKey: id)?.resume(returning: state(of: token))
    }

    /// Reads `listen = "<path>"` from the pool file and binds a Unix socket there.
    private static func bindPoolSocket(_ request: ProcessRequest) throws -> (Int32, String) {
        guard let index = request.arguments.firstIndex(of: "-y") else { throw JerdError.invalid("No pool file.") }
        let text = try String(contentsOfFile: request.arguments[index + 1], encoding: .utf8)
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix("listen = ") }) else {
            throw JerdError.invalid("No listen line.")
        }
        let path = String(line.dropFirst("listen = \"".count).dropLast())
        return (try FakeFPMServer.listen(at: URL(fileURLWithPath: path)), path)
    }
}
