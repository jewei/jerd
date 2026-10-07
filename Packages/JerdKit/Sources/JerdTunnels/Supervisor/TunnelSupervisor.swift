import Foundation
import JerdFoundation

/// Controls Jerd's connectors for existing remote Cloudflare tunnels.
///
/// Rules:
/// - No method changes a Cloudflare account, a remote tunnel, a route, or DNS.
/// - Tokens live in the secret store, never in settings, arguments, or logs.
/// - Load and Save never connect. `connectStartupTunnels()` connects only on request.
/// - Each tunnel has one work slot keyed by generation, and one reducer
///   (`TunnelReconnectPolicy`) decides every state change.
/// - Stop is graceful and stops only connectors that Jerd started. A connector that does not stop
///   stays owned, Remove is refused, and `stopAll()` throws so that Quit is cancelled.
public actor TunnelSupervisor {
    let store: TunnelStore
    let secrets: any TunnelSecretStoring
    let connector: any TunnelConnecting
    let policy: TunnelReconnectPolicy
    let clock: any TunnelClocking
    let root: URL

    var configuration = TunnelConfiguration() {
        didSet { publishSnapshots() }
    }
    var loaded = false
    var editing = false
    var shuttingDown = false
    var lifecycles: [UUID: TunnelLifecycle] = [:] {
        didSet { publishSnapshots() }
    }
    /// Connectors that Jerd owns, also after a failed stop.
    var handles: [UUID: TunnelConnectorHandle] = [:] {
        didSet { publishSnapshots() }
    }
    var slots = TunnelWorkSlots()
    var stops: [UUID: TunnelStopWork] = [:]
    var lastGeneration: UInt64 = 0
    /// The streams of `snapshotUpdates()`, by subscription.
    var observers: [UUID: AsyncStream<[TunnelSnapshot]>.Continuation] = [:]

    public init(
        layout: TunnelsLayout, secrets: any TunnelSecretStoring = TunnelSecretStore(),
        connector: (any TunnelConnecting)? = nil, policy: TunnelReconnectPolicy = .standard,
        clock: any TunnelClocking = TunnelClock()
    ) {
        store = TunnelStore(layout: layout)
        self.secrets = secrets
        self.connector = connector ?? CloudflaredConnector(layout: layout)
        self.policy = policy
        self.clock = clock
        root = layout.root
    }

    /// Reads the settings once. It never connects a tunnel, also not one with `startOnLaunch`.
    /// - Throws: `.corrupt` when the file cannot be read. The file stays as it is.
    @discardableResult
    public func load() throws -> TunnelConfiguration {
        if loaded { return configuration }
        try beginEdit()
        defer { editing = false }
        configuration = try store.load()
        try OwnedDirectory.create(root)
        loaded = true
        return configuration
    }

    /// The settings as last loaded or saved.
    public func currentConfiguration() -> TunnelConfiguration { configuration }

    /// One snapshot per registration, in settings order.
    public func snapshots() -> [TunnelSnapshot] {
        configuration.tunnels.map { registration in
            TunnelSnapshot(
                registration: registration, state: lifecycles[registration.id]?.state ?? .stopped,
                processID: handles[registration.id]?.processID)
        }
    }

    /// A free metrics port from 20241 that no registration uses.
    public func suggestedPort() async throws -> UInt16 {
        try requireLoaded()
        let reserved = Set(configuration.tunnels.map(\.metricsPort))
        return try await connector.suggestPort(startingAt: TunnelRegistration.defaultMetricsPort, excluding: reserved)
    }

    /// Checks `executable` (`cloudflared --version`) and saves it as the runtime of every tunnel.
    /// The installer and the file picker both use this, so one runtime always gets one ID.
    @discardableResult
    public func useRuntime(at executable: URL) async throws -> TunnelRuntime {
        try requireLoaded()
        try beginEdit()
        defer { editing = false }
        guard !hasAnyConnection else { throw JerdError.unavailable(TunnelMessage.runtimeInUse) }
        let runtime = try await connector.inspectRuntime(executable: executable)
        var next = configuration
        next.runtime = runtime
        try store.save(next)
        configuration = next
        return runtime
    }

    /// The recent output of this and earlier connector runs (64 KiB).
    public func log(id: UUID) async throws -> String {
        try requireLoaded()
        guard configuration.registration(id) != nil else { throw JerdError.invalid(TunnelMessage.notRegistered) }
        return try await connector.history(for: id) ?? TunnelMessage.noLog
    }

    // MARK: Shared guards

    var hasAnyConnection: Bool {
        !handles.isEmpty || !slots.isEmpty || !stops.isEmpty || lifecycles.values.contains { $0.generation != nil }
    }

    /// True while a connector runs, a Connect or Stop is in progress, or a connection is wanted.
    func isActive(_ id: UUID) -> Bool {
        handles[id] != nil || slots.generation(of: id) != nil || stops[id] != nil || lifecycles[id]?.generation != nil
    }

    func requireLoaded() throws {
        guard loaded else { throw JerdError.unavailable(TunnelMessage.notLoaded) }
    }

    func beginEdit() throws {
        guard !editing, !shuttingDown else { throw JerdError.unavailable(TunnelMessage.busy) }
        editing = true
    }

    /// Runs the reducer and keeps its result. Returns the next step.
    @discardableResult
    func apply(_ event: TunnelEvent, to id: UUID) -> TunnelStep {
        let transition = policy.reduce(lifecycles[id] ?? .idle, event, now: clock.now)
        lifecycles[id] = transition.lifecycle
        return transition.step
    }

    func isCurrent(_ generation: TunnelGeneration, _ id: UUID) -> Bool {
        lifecycles[id]?.generation == generation
    }

    func makeGeneration() -> TunnelGeneration {
        lastGeneration += 1
        return TunnelGeneration(lastGeneration)
    }
}
