import Foundation

public struct TunnelMonitorPolicy: Sendable {
    public let interval: Duration
    public let retryDelays: [Duration]
    public init(interval: Duration = .seconds(5), retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15), .seconds(30), .seconds(60)]) {
        self.interval = interval; self.retryDelays = retryDelays.isEmpty ? [.seconds(60)] : retryDelays
    }
}

/// Controls existing remote tunnel connectors. Hostnames and origins are descriptive only;
/// no method changes a Cloudflare account, a remote tunnel, or DNS.
public actor TunnelManager {
    public let directory: URL
    private let store: TunnelStore
    private let secrets: any TunnelSecretStoring
    private let transport: any TunnelTransport
    private let policy: TunnelMonitorPolicy
    private var configuration = TunnelConfiguration()
    private var states: [UUID: TunnelState] = [:]
    private var running: [UUID: TunnelProcess] = [:]
    private var desired: [UUID: UUID] = [:]
    private var starts: [UUID: Task<Void, Error>] = [:]
    private var stops: [UUID: Task<Void, Error>] = [:]
    private var monitors: [UUID: Task<Void, Never>] = [:]
    private var loaded = false
    private var editing = false
    private var shuttingDown = false

    public init(directory: URL, secrets: any TunnelSecretStoring = TunnelKeychainStore(),
                transport: any TunnelTransport = TunnelLocalTransport(), policy: TunnelMonitorPolicy = .init()) {
        self.directory = directory; store = TunnelStore(directory: directory)
        self.secrets = secrets; self.transport = transport; self.policy = policy
    }
    public func load() async throws -> TunnelConfiguration {
        if loaded { return configuration }
        try beginEdit(); defer { editing = false }
        configuration = try await store.load()
        try PrivateFiles.directory(directory)
        loaded = true
        return configuration
    }
    public func configurationSnapshot() -> TunnelConfiguration { configuration }
    public func snapshots() -> [TunnelSnapshot] {
        configuration.tunnels.map { TunnelSnapshot(registration: $0, state: states[$0.id] ?? .stopped, processID: running[$0.id]?.processID) }
    }
    public func suggestedPort() async throws -> UInt16 {
        try requireLoaded()
        return try await transport.availablePort(startingAt: 20241, excluding: Set(configuration.tunnels.map(\.metricsPort)), directory: directory)
    }
    public func inspectRuntime(executable: URL) async throws -> TunnelRuntime {
        try await transport.inspectRuntime(executable: executable, directory: directory)
    }
    public func registerRuntime(_ runtime: TunnelRuntime) async throws {
        try requireLoaded(); try beginEdit(); defer { editing = false }
        guard running.isEmpty, desired.isEmpty, starts.isEmpty else { throw JerdError.unavailable("Stop all tunnels before changing cloudflared.") }
        var next = configuration; next.runtime = runtime
        try await store.save(next); configuration = next
    }
    public func save(_ registration: TunnelRegistration, token: String? = nil) async throws {
        try requireLoaded(); try beginEdit(); defer { editing = false }
        guard desired[registration.id] == nil, running[registration.id] == nil, starts[registration.id] == nil else {
            throw JerdError.unavailable("Stop the tunnel before changing its settings.")
        }
        try registration.validate()
        var next = configuration
        if let index = next.tunnels.firstIndex(where: { $0.id == registration.id }) { next.tunnels[index] = registration }
        else { next.tunnels.append(registration) }
        try next.validate()
        let previous = try await secrets.read(id: registration.id)
        if let token {
            try Self.validateToken(token)
            // Reject duplicate remote tunnel IDs even when a token has been rotated.
            for other in configuration.tunnels where other.id != registration.id {
                if let otherToken = try await secrets.read(id: other.id),
                   TunnelTokenPayload.decode(otherToken)?.t == TunnelTokenPayload.decode(token)?.t {
                    throw JerdError.invalid("This Cloudflare tunnel is already saved in Jerd.")
                }
            }
            try await secrets.write(token, id: registration.id)
        } else if previous == nil { throw JerdError.invalid("Enter the existing tunnel token.") }
        do { try await store.save(next); configuration = next; states[registration.id] = .stopped }
        catch {
            if token != nil {
                if let previous { try? await secrets.write(previous, id: registration.id) }
                else { try? await secrets.remove(id: registration.id) }
            }
            throw error
        }
    }
    public func remove(id: UUID) async throws {
        try requireLoaded(); try beginEdit(); defer { editing = false }
        guard desired[id] == nil, running[id] == nil, starts[id] == nil else { throw JerdError.unavailable("Stop the tunnel before removing it from Jerd.") }
        guard configuration.tunnels.contains(where: { $0.id == id }) else { return }
        let previous = try await secrets.read(id: id)
        var next = configuration; next.tunnels.removeAll { $0.id == id }
        try await secrets.remove(id: id)
        do { try await store.save(next); configuration = next; states[id] = nil }
        catch {
            if let previous { try? await secrets.write(previous, id: id) }
            throw error
        }
        // Logs and ownership records are retained for inspection. No remote resource is removed.
    }
    public func start(id: UUID) async throws {
        try requireLoaded()
        guard !editing, !shuttingDown else { throw JerdError.unavailable("Wait for the current tunnel operation to finish.") }
        guard configuration.tunnels.contains(where: { $0.id == id }) else { throw JerdError.invalid("The tunnel is not registered.") }
        guard desired[id] == nil, starts[id] == nil, stops[id] == nil, running[id] == nil else { throw JerdError.unavailable("This tunnel already has a connection or a pending operation.") }
        guard configuration.runtime != nil else { throw JerdError.unavailable("Install or select cloudflared before connecting.") }
        let generation = UUID(); desired[id] = generation; states[id] = .starting
        let task = Task { try await self.connect(id: id, generation: generation) }
        starts[id] = task
        do {
            try await task.value
            starts[id] = nil
            if desired[id] == generation { monitor(id: id, generation: generation) }
        } catch {
            starts[id] = nil
            if desired[id] == generation {
                states[id] = .failed(safeError(error))
                // Configuration or process setup errors require an explicit retry. Network loss is handled after launch.
                desired[id] = nil
            }
            throw error
        }
    }
    public func stop(id: UUID) async throws {
        try requireLoaded()
        if let task = stops[id] { return try await task.value }
        let task = Task { try await self.performStop(id: id) }
        stops[id] = task
        defer { stops[id] = nil }
        try await task.value
    }
    private func performStop(id: UUID) async throws {
        desired[id] = nil
        monitors.removeValue(forKey: id)?.cancel()
        states[id] = .stopping
        if let task = starts[id] {
            task.cancel()
            _ = await task.result
            starts[id] = nil
        }
        do { try await stopOwned(id); states[id] = .stopped }
        catch { states[id] = .failed(safeError(error)); throw error }
    }
    public func stopAll() async throws {
        shuttingDown = true
        defer { shuttingDown = false }
        desired.removeAll()
        for task in monitors.values { task.cancel() }
        monitors.removeAll()
        for task in starts.values { task.cancel() }
        var failures: [String] = []
        for id in configuration.tunnels.map(\.id) {
            do { try await stop(id: id) } catch { failures.append(safeError(error)) }
        }
        if !failures.isEmpty { throw JerdError.process(failures.joined(separator: "\n")) }
    }
    public func log(id: UUID) throws -> String {
        try requireLoaded()
        guard configuration.tunnels.contains(where: { $0.id == id }) else { throw JerdError.invalid("The tunnel is not registered.") }
        let file = paths(id).log
        guard PrivateFiles.exists(file) else { return "No connection log yet." }
        return try ProcessLog.read(file, limit: 65_536, tail: true)
    }
    private func connect(id: UUID, generation: UUID) async throws {
        guard desired[id] == generation, let registration = configuration.tunnels.first(where: { $0.id == id }), let runtime = configuration.runtime else { throw CancellationError() }
        guard let token = try await secrets.read(id: id) else { throw JerdError.unavailable("The tunnel token is missing. Edit this tunnel to add its token.") }
        try Self.validateToken(token)
        guard desired[id] == generation, !Task.isCancelled else { throw CancellationError() }
        let process: TunnelProcess
        do { process = try await transport.start(runtime: runtime, registration: registration, token: token, paths: paths(id)) }
        catch {
            running[id] = await transport.ownedProcess(registrationID: id)
            throw JerdError.process(redact(error.localizedDescription, token: token))
        }
        running[id] = process
        guard desired[id] == generation, !Task.isCancelled else {
            try await stopOwned(id)
            throw CancellationError()
        }
        states[id] = .starting
    }
    private func monitor(id: UUID, generation: UUID) {
        monitors[id]?.cancel()
        monitors[id] = Task { [weak self] in
            var retries = 0
            var connectedSince: ContinuousClock.Instant?
            while !Task.isCancelled {
                guard let self else { return }
                let action = await self.check(id: id, generation: generation)
                switch action {
                case .done: return
                case .poll(let connected):
                    if connected {
                        if let since = connectedSince, ContinuousClock.now - since >= .seconds(30) { retries = 0 }
                        else if connectedSince == nil { connectedSince = ContinuousClock.now }
                    } else { connectedSince = nil }
                    do { try await Task.sleep(for: self.policy.interval) } catch { return }
                case .retry:
                    connectedSince = nil
                    let delay = self.policy.retryDelays[min(retries, self.policy.retryDelays.count - 1)]
                    retries += 1
                    do { try await Task.sleep(for: delay) } catch { return }
                    await self.retry(id: id, generation: generation)
                }
            }
        }
    }
    private enum MonitorAction { case done, poll(connected: Bool), retry }
    private func check(id: UUID, generation: UUID) async -> MonitorAction {
        guard desired[id] == generation, let registration = configuration.tunnels.first(where: { $0.id == id }) else { return .done }
        guard let process = running[id] else { return .retry }
        let alive = await transport.isRunning(process)
        guard desired[id] == generation else { return .done }
        let tail = (try? log(id: id)) ?? ""
        if TunnelDriver.authenticationFailed(tail) {
            desired[id] = nil
            do { try await stopOwned(id); states[id] = .failed("Cloudflare rejected the tunnel token. Edit this tunnel to replace its token.") }
            catch { states[id] = .failed("Cloudflare rejected the token. " + safeError(error)) }
            return .done
        }
        if !alive {
            do { try await stopOwned(id) }
            catch { desired[id] = nil; states[id] = .failed(safeError(error)); return .done }
            guard desired[id] == generation else { return .done }
            // The private log pipe can still hold the last message until the exited child is reaped.
            if TunnelDriver.authenticationFailed((try? log(id: id)) ?? "") {
                desired[id] = nil
                states[id] = .failed("Cloudflare rejected the tunnel token. Edit this tunnel to replace its token.")
                return .done
            }
            if registration.restartOnFailure { states[id] = .reconnecting; return .retry }
            desired[id] = nil; states[id] = .failed("The tunnel process exited. Select Connect to try again."); return .done
        }
        do {
            let ready = try await transport.isReady(process, registration: registration, paths: paths(id))
            guard desired[id] == generation, running[id] == process else { return .done }
            states[id] = ready ? .connected : .reconnecting
        } catch is TunnelTransportError {
            guard desired[id] == generation, running[id] == process else { return .done }
            desired[id] = nil
            do { try await stopOwned(id) } catch { /* Keep the owned handle for an explicit Stop retry. */ }
            states[id] = .failed("The tunnel opened an unexpected listener. Jerd requested a graceful stop. Check its log before retrying.")
            return .done
        } catch {
            guard desired[id] == generation else { return .done }
            // Metrics may be absent during startup, or the network may be unavailable.
            // Never call the public address or infer application health from this result.
            states[id] = .reconnecting
        }
        return .poll(connected: states[id] == .connected)
    }
    private func retry(id: UUID, generation: UUID) async {
        guard desired[id] == generation, starts[id] == nil else { return }
        let task = Task { try await self.connect(id: id, generation: generation) }
        starts[id] = task
        do { try await task.value }
        catch {
            if desired[id] == generation { states[id] = .reconnecting }
        }
        starts[id] = nil
    }
    private func stopOwned(_ id: UUID) async throws {
        guard let process = running[id] else { return }
        try await transport.stop(process, paths: paths(id))
        if running[id] == process { running[id] = nil }
    }
    private func paths(_ id: UUID) -> TunnelPaths {
        TunnelPaths(root: directory.appendingPathComponent("instances").appendingPathComponent(id.uuidString))
    }
    private func requireLoaded() throws {
        guard loaded else { throw JerdError.unavailable("Load tunnel settings before changing a tunnel.") }
    }
    private func beginEdit() throws {
        guard !editing, !shuttingDown else { throw JerdError.unavailable("Wait for the current tunnel operation to finish.") }
        editing = true
    }
    private static func validateToken(_ token: String) throws {
        guard !token.isEmpty, token.utf8.count <= 16_384, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw JerdError.invalid("Paste the tunnel token without spaces or a command.")
        }
        guard let payload = TunnelTokenPayload.decode(token), !payload.a.isEmpty, !payload.s.isEmpty else {
            throw JerdError.invalid("The token format is invalid. Copy the token for an existing remotely managed Cloudflare tunnel.")
        }
    }
    private func redact(_ message: String, token: String) -> String {
        TunnelDriver.redactedValues(token).reduce(message) { $0.replacingOccurrences(of: $1, with: "[REDACTED]") }
    }
    private func safeError(_ error: any Error) -> String {
        error is CancellationError ? "The tunnel operation was cancelled." : error.localizedDescription
    }
}
