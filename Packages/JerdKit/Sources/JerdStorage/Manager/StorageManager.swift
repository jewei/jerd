import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// Owns the one local RustFS service and its registered buckets.
///
/// Rules:
/// - Every call except `load` and `snapshot` requires loaded settings.
/// - One operation runs at a time. Exit detection in `snapshot()` is not an operation: it never
///   waits for a stop, so it never blocks Stop or Quit.
/// - While a runtime update needs recovery, only `load`, `start`, and `stop` run; `load` and
///   `start` recover it first.
/// - Saving a bucket starts storage when needed. A bucket is complete only after RustFS confirms
///   it and its access policy. A missing complete bucket is reported, never created again.
/// - Stop and Quit keep every bucket, object, and credential.
public actor StorageManager {
    /// The items that a runtime update backs up, in order.
    static let updateItems = [
        ServiceFileName.settings, ServiceFileName.previousSettings, ServiceFileName.data,
        ServiceFileName.runtimeIdentity, ServiceFileName.initializedMarker, ServiceFileName.credentials, "access-key",
        "secret-key",
    ]

    public nonisolated let layout: StorageLayout
    let dataRoot: URL
    let effects: ServiceEffects
    let sender: any S3Sending
    let now: @Sendable () -> Date
    let store: StorageSettingsStore
    let transaction: RuntimeUpdateTransaction
    /// The bucket names of the current launch.
    let listed = ListedBuckets()
    var settings = StorageSettings()
    /// The managed instance. It exists once a runtime is saved.
    var instance: ManagedInstance?
    var loaded = false
    var busy = false

    /// - Parameters:
    ///   - layout: the data layout; storage lives in `layout.storage`.
    ///   - sender: the HTTP transport to RustFS. The default is a new `S3Transport`.
    ///   - now: the clock of request signatures.
    public init(
        layout: DataLayout, effects: ServiceEffects, sender: (any S3Sending)? = nil,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let storage = layout.storage
        self.layout = storage
        dataRoot = layout.root
        self.effects = effects
        self.sender = sender ?? S3Transport()
        self.now = now
        store = StorageSettingsStore(layout: storage)
        transaction = RuntimeUpdateTransaction(
            root: storage.root, journalFile: storage.runtimeUpdateJournal,
            backupsDirectory: storage.runtimeBackupsDirectory, lockFile: storage.lockFile, names: Self.updateItems,
            messages: StorageMessages.update)
    }

    /// Loads the settings once, creates `storage/` (mode 0700), and recovers an unfinished runtime
    /// update. Later calls return the loaded settings.
    public func load() async throws -> StorageSettings {
        guard !loaded else { return settings }
        try begin(allowingRecovery: true)
        defer { busy = false }
        try OwnedDirectory.create(layout.root)
        settings = try store.load()
        if let runtime = settings.runtime { instance = makeInstance(runtime: runtime, ports: settings.ports) }
        try await recoverPendingUpdate()
        loaded = true
        return settings
    }

    /// The settings, the state, and the listed buckets. It also detects an unexpected exit.
    ///
    /// The snapshot shows listed names only while RustFS runs. It never clears them itself,
    /// because a readiness probe can fill them while the state is still `starting`.
    public func snapshot() async -> StorageSnapshot {
        let state = await instance?.refresh() ?? .stopped
        return StorageSnapshot(settings: settings, state: state, availableBuckets: listed.current)
    }

    // MARK: Helpers

    /// Runs `body` as the one operation in progress.
    func exclusive<Result>(allowingRecovery: Bool = false, _ body: () async throws -> Result) async throws -> Result {
        guard loaded else { throw StorageMessages.notLoaded }
        try begin(allowingRecovery: allowingRecovery)
        defer { busy = false }
        return try await body()
    }

    private func begin(allowingRecovery: Bool) throws {
        guard !busy else { throw JerdError.unavailable(StorageMessages.busy) }
        guard allowingRecovery || !transaction.isPending else { throw StorageMessages.updatePending }
        busy = true
    }

    func definition(runtime: StorageRuntime, ports: StoragePorts) -> RustFSDefinition {
        RustFSDefinition(
            runtime: runtime, ports: ports, layout: layout, dataRoot: dataRoot, sender: sender, listed: listed,
            now: now)
    }

    func makeInstance(runtime: StorageRuntime, ports: StoragePorts) -> ManagedInstance {
        ManagedInstance(definition: definition(runtime: runtime, ports: ports), effects: effects)
    }

    /// Saves `next` and keeps it as the current settings.
    func save(_ next: StorageSettings, replacing previous: StorageRuntime? = nil) throws {
        try store.save(next, replacing: previous)
        settings = next
    }

    /// Restores an unfinished runtime update. Without a journal it does nothing.
    func recoverPendingUpdate() async throws {
        guard transaction.isPending else { return }
        guard let instance else { throw StorageMessages.recoveryWithoutRuntime }
        try await transaction.recoverIfNeeded(on: instance, reload: { try await self.reloadDefinition() })
    }

    /// Reloads the saved settings, for example after a restore, and returns their definition.
    func reloadDefinition() throws -> any ServiceDefinition {
        let restored = try store.load()
        guard let runtime = restored.runtime else { throw StorageMessages.recoveryWithoutRuntime }
        settings = restored
        return definition(runtime: runtime, ports: restored.ports)
    }
}
