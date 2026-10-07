import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// Owns the one local RustFS service and its registered buckets.
///
/// The shared `SingleServiceCoordinator` holds the rules that Mail and Storage share:
/// - Every call except `load` and `snapshot` requires loaded settings.
/// - One operation runs at a time. Exit detection in `snapshot()` is not an operation: it never
///   waits for a stop, so it never blocks Stop or Quit.
/// - While a runtime update needs recovery, only `load`, `start`, and `stop` run; `load` and
///   `start` recover it first.
///
/// Storage adds:
/// - Each launch has its own S3 session. Every kind of stop ends it and clears the listed names.
/// - Saving a bucket starts storage when needed. A bucket is complete only after RustFS confirms
///   it and its access policy. A missing complete bucket is reported, never created again.
/// - Stop and Quit keep every bucket, object, and credential.
public actor StorageManager {
    typealias Coordinator = SingleServiceCoordinator<StorageService>

    public nonisolated let layout: StorageLayout
    nonisolated let effects: ServiceEffects
    nonisolated let now: @Sendable () -> Date
    /// The S3 session and the bucket names of the current launch.
    nonisolated let launch = StorageLaunch()
    nonisolated let coordinator: Coordinator

    /// - Parameters:
    ///   - layout: the data layout; storage lives in `layout.storage`.
    ///   - sender: an HTTP transport to RustFS that every launch shares. The default gives each
    ///     launch a new `S3Transport`, which the end of the launch invalidates.
    ///   - now: the clock of request signatures.
    public init(
        layout: DataLayout, effects: ServiceEffects, sender: (any S3Sending)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let makeSession: @Sendable () -> S3Session
        if let sender {
            makeSession = { S3Session.shared(sender) }
        } else {
            makeSession = { S3Session.transport() }
        }
        self.init(layout: layout, effects: effects, makeSession: makeSession, now: now)
    }

    /// - Parameter makeSession: a new S3 session for each launch.
    init(
        layout: DataLayout, effects: ServiceEffects, makeSession: @escaping @Sendable () -> S3Session,
        now: @escaping @Sendable () -> Date
    ) {
        let storage = layout.storage
        self.layout = storage
        self.effects = effects
        self.now = now
        let service = StorageService(
            layout: storage, dataRoot: layout.root, launch: launch, makeSession: makeSession, now: now)
        coordinator = Coordinator(service: service, effects: effects, settings: StorageSettings())
    }

    /// Loads the settings once, creates `storage/` (mode 0700), and recovers an unfinished runtime
    /// update. Later calls return the loaded settings.
    public func load() async throws -> StorageSettings {
        try await coordinator.load()
    }

    /// The settings, the state, and the listed buckets. It also detects an unexpected exit.
    ///
    /// The snapshot shows listed names only while RustFS runs, because a readiness probe can fill
    /// them while the state is still `starting`.
    public func snapshot() async -> StorageSnapshot {
        let current = await coordinator.snapshot()
        return StorageSnapshot(settings: current.settings, state: current.state, availableBuckets: launch.names)
    }

    /// Saves the first installed runtime with two free suggested ports. A saved runtime never
    /// changes here; a new runtime goes through `updateRuntime(_:)`.
    public func registerRuntime(_ runtime: StorageRuntime) async throws {
        try await coordinator.registerRuntime(runtime)
    }

    /// The first free API port from 9000 and the first other free console port from 9001.
    public func suggestedPorts() async throws -> StoragePorts {
        try await coordinator.suggestedPorts()
    }

    /// Moves stopped storage to two other free ports. A failure message is cleared. The run
    /// record is checked with the storage lock held.
    public func edit(ports: StoragePorts) async throws {
        try await coordinator.edit(ports: ports)
    }

    /// Replaces the RustFS runtime as a journaled transaction.
    ///
    /// The data is first checked against the saved runtime without a write, so storage that
    /// never started gets no data or credentials here. The settings, the data, the markers, and
    /// the credentials are backed up off this actor (APFS clones when the volume supports them),
    /// and the new runtime must pass a full start and list every complete bucket. The backup
    /// stays until the user deletes it in Advanced.
    public func updateRuntime(_ runtime: StorageRuntime) async throws {
        try await coordinator.updateRuntime(runtime)
    }
}
