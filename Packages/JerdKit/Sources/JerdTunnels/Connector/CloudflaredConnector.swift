import Darwin
import Foundation
import JerdFoundation
import JerdProcess

/// Starts and stops cloudflared connectors for existing tunnels. It owns only the processes
/// that it started and never signals any other cloudflared on the Mac.
///
/// A launch holds `service.lock`, refuses to start beside a live earlier process, checks the runtime
/// version and that the metrics port is free, writes the private `config.yml`, keeps the earlier log,
/// spawns cloudflared in its own process group, and saves `active-run.json`. A stop is graceful
/// (SIGTERM, 30 s, never SIGKILL); a timeout keeps the process, its lock, and its record.
public actor CloudflaredConnector: TunnelConnecting {
    static let lockMessages = InstanceLock.Messages(
        unavailable: TunnelMessage.lockUnavailable, busy: TunnelMessage.lockBusy)
    /// The most log bytes that one read returns (64 KiB).
    package static let logViewBytes = 65_536

    let layout: TunnelsLayout
    let processes: any ProcessControlling
    let commands: any CommandRunning
    let ports: LoopbackPortGuard
    let gate: StartGate
    let recorder: ActiveRunRecorder
    let stopPolicy: StopPolicy
    let sites: any TunnelSiteResolving
    /// Connectors that run, by registration ID.
    var owned: [UUID: OwnedConnector] = [:]
    /// Registrations with a launch in progress, so a second launch cannot begin.
    var launching: Set<UUID> = []

    /// - Parameter sites: Resolves the linked site of a local route at each launch.
    package init(
        layout: TunnelsLayout, sites: any TunnelSiteResolving, processes: any ProcessControlling = ProcessSupervisor(),
        commands: any CommandRunning = CommandRunner(), ports: LoopbackPortGuard = LoopbackPortGuard(),
        gate: StartGate = StartGate(), recorder: ActiveRunRecorder = ActiveRunRecorder(),
        stopPolicy: StopPolicy = .graceful()
    ) {
        self.layout = layout
        self.processes = processes
        self.commands = commands
        self.ports = ports
        self.gate = gate
        self.recorder = recorder
        self.stopPolicy = stopPolicy
        self.sites = sites
    }

    public func inspectRuntime(executable: URL) async throws -> TunnelRuntime {
        guard CloudflaredCommand.isCandidate(executable) else { throw JerdError.invalid(TunnelMessage.executableName) }
        try OwnedDirectory.create(layout.root)
        let request = CloudflaredCommand.version(executable: executable, workingDirectory: layout.root)
        let result = try await commands.run(request, timeout: CloudflaredCommand.versionTimeout)
        guard result.succeeded, let version = CloudflaredCommand.parseVersion(result.output) else {
            throw JerdError.invalid(TunnelMessage.noVersion)
        }
        return TunnelRuntime(version: version, directory: executable.deletingLastPathComponent())
    }

    public func suggestPort(startingAt first: UInt16, excluding reserved: Set<UInt16>) async throws -> UInt16 {
        try await ports.suggest(startingAt: first, excluding: reserved)
    }

    public func connect(_ launch: TunnelLaunch) async throws -> TunnelConnectorHandle {
        let id = launch.registration.id
        guard owned[id] == nil, !launching.contains(id) else {
            throw JerdError.unavailable(TunnelMessage.previousProcess)
        }
        launching.insert(id)
        defer { launching.remove(id) }
        let instance = layout.instance(id)
        try OwnedDirectory.create(instance.root)
        try OwnedDirectory.create(instance.homeDirectory)
        let lock = try InstanceLock.acquire(at: instance.lockFile, messages: Self.lockMessages)
        do {
            // The record check runs first, before any command, while the lock is held.
            let clearance = try gate.requireStopped(instance.record, holding: lock)
            try await prepare(launch, instance: instance)
            return try await spawn(launch, instance: instance, lock: lock, clearance: clearance)
        } catch {
            if owned[id] == nil { lock.release() }
            throw error
        }
    }

    public func ownedHandle(for id: UUID) -> TunnelConnectorHandle? { owned[id]?.handle }

    public func isRunning(_ handle: TunnelConnectorHandle) async -> Bool {
        guard owned[handle.registrationID]?.handle == handle else { return false }
        return await processes.state(of: handle.process) == .running
    }

    public func disconnect(_ handle: TunnelConnectorHandle) async throws {
        let id = handle.registrationID
        guard owned[id]?.handle == handle else { return }
        let outcome = await processes.stop(handle.process, policy: stopPolicy)
        // Another disconnect of the same handle can finish while this one waits.
        guard let entry = owned[id], entry.handle == handle else { return }
        if case .timedOut = outcome { throw JerdError.processFailed(TunnelMessage.notStopped) }
        owned[id] = nil
        defer { entry.lock.release() }
        // After `.notOwned`, something else reaped the leader. The record stays, so the next
        // launch or Process recovery checks for group members before any new process runs.
        if outcome == .stopped { try ActiveRunRecordFile.remove(entry.record, holding: entry.lock) }
    }

    public func currentOutput(for id: UUID) throws -> String {
        try ProcessLogFile(url: layout.instance(id).logFile).readTail(limit: Self.logViewBytes)
    }

    public func history(for id: UUID) throws -> String? {
        try ConnectorLogHistory(instance: layout.instance(id)).recent(limit: Self.logViewBytes)
    }

    /// Checks the runtime and the port, writes this launch's `config.yml`, and keeps the earlier log.
    private func prepare(_ launch: TunnelLaunch, instance: TunnelInstanceLayout) async throws {
        let inspected = try await inspectRuntime(executable: launch.runtime.executable)
        guard inspected.version == launch.runtime.version else {
            throw JerdError.unavailable(TunnelMessage.versionMismatch)
        }
        try await ports.requireFree(launch.registration.metricsPort)
        let route = try await route(for: launch.registration)
        try AtomicFile.write(CloudflaredConfigurationRenderer.render(route), to: instance.configurationFile)
        try ConnectorLogHistory(instance: instance).archiveCurrent()
        try Task.checkCancellation()
    }

    /// The route of this launch. A linked site is resolved at every launch, also for a retry after
    /// an unexpected exit, so the route uses the site as the web run serves it now.
    private func route(for registration: TunnelRegistration) async throws -> TunnelRoute {
        guard let local = try registration.localRoute() else { return .cloudflare }
        switch local.target {
        case .site(let siteID):
            return .site(local.hostname, try await sites.prepareDestination(for: siteID))
        case .address(let origin):
            return .address(local.hostname, origin: origin)
        }
    }

    /// Spawns cloudflared, takes ownership, and saves the run record.
    private func spawn(
        _ launch: TunnelLaunch, instance: TunnelInstanceLayout, lock: InstanceLock, clearance: StartClearance
    ) async throws -> TunnelConnectorHandle {
        let request = CloudflaredCommand.connector(launch, instance: instance)
        let process = try await processes.start(request, log: ProcessLogFile(url: instance.logFile))
        guard let processID = await processes.processID(of: process) else {
            // Without a PID the child is not owned, so this stop only releases the supervisor entry.
            // A crash at start can pass on a later try, so the failure is marked as retryable.
            _ = await processes.stop(process, policy: stopPolicy)
            throw TunnelRetryableError(.processFailed(TunnelMessage.exitedEarly))
        }
        let handle = TunnelConnectorHandle(
            registrationID: launch.registration.id, process: process, processID: processID,
            metricsPort: launch.registration.metricsPort)
        owned[launch.registration.id] = OwnedConnector(handle: handle, lock: lock, record: instance.record)
        do {
            try recorder.record(
                processID: processID, runtimeID: launch.runtime.id, gracefulSignal: SIGTERM, clearance: clearance)
        } catch {
            // A connector without a complete record must not keep running. If it does not stop,
            // it stays owned for an explicit Stop, and the stop error is reported instead.
            try await disconnect(handle)
            throw error
        }
        return handle
    }
}
