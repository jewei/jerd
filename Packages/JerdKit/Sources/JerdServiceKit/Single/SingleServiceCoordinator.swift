import Foundation
import JerdFoundation

/// The one manager core of a single-instance service (Mail, Storage): the loaded settings, the
/// managed instance, one operation at a time, port edits, runtime registration, runtime updates,
/// and update recovery.
///
/// Rules:
/// - Every operation except `load` and `snapshot` requires loaded settings.
/// - One operation runs at a time (`exclusive`). Exit detection in `snapshot()` is not an
///   operation: it never waits for a stop, so it never blocks Stop or Quit.
/// - While a runtime update needs recovery, only `load`, `start`, and `stop` run; `load` and
///   `start` recover it first.
/// - Settings change only inside an operation, through `save(_:replacing:)`.
package actor SingleServiceCoordinator<Service: SingleServiceDescribing> {
    package typealias Settings = Service.Settings
    package typealias Runtime = Settings.Runtime
    package typealias Ports = Settings.Ports

    package nonisolated let service: Service
    package nonisolated let effects: ServiceEffects
    package nonisolated let transaction: RuntimeUpdateTransaction
    package private(set) var settings: Settings
    /// The managed instance. It exists once a runtime is saved.
    package private(set) var instance: ManagedInstance?
    package private(set) var loaded = false
    private var busy = false

    /// - Parameter settings: the settings before `load()`, normally the defaults.
    package init(service: Service, effects: ServiceEffects, settings: Settings) {
        self.service = service
        self.effects = effects
        self.settings = settings
        transaction = service.updateTransaction
    }

    package nonisolated var messages: SingleServiceMessages { service.messages }

    /// Loads the settings once, creates the service folder (mode 0700), and recovers an
    /// unfinished runtime update. Later calls return the loaded settings.
    package func load() async throws -> Settings {
        guard !loaded else { return settings }
        try begin(allowingRecovery: true)
        defer { busy = false }
        try OwnedDirectory.create(service.root)
        settings = try service.loadSettings()
        if let runtime = settings.runtime { instance = makeInstance(runtime: runtime, ports: settings.ports) }
        try await recoverPendingUpdate()
        loaded = true
        return settings
    }

    /// The settings and the state. It also detects an unexpected exit of the process.
    package func snapshot() async -> (settings: Settings, state: ServiceState) {
        let state = await instance?.refresh() ?? .stopped
        return (settings, state)
    }

    /// Throws `notLoaded` before `load()`.
    package func requireLoaded() throws {
        guard loaded else { throw messages.notLoaded }
    }

    /// Runs `body` as the one operation in progress, on this actor.
    ///
    /// - Parameter allowingRecovery: true for the operations that may run while a runtime update
    ///   needs recovery (start and stop).
    package func exclusive<Result: Sendable>(
        allowingRecovery: Bool = false, _ body: @Sendable (isolated SingleServiceCoordinator) async throws -> Result
    ) async throws -> Result {
        try requireLoaded()
        try begin(allowingRecovery: allowingRecovery)
        defer { busy = false }
        return try await body(self)
    }

    /// Saves `next` and keeps it as the current settings. Only inside `exclusive`.
    package func save(_ next: Settings, replacing previous: Runtime? = nil) throws {
        guard busy else { throw JerdError.unavailable(messages.busy) }
        try service.save(next, replacing: previous)
        settings = next
    }

    /// The instance of the saved runtime.
    package func requireInstance() throws -> ManagedInstance {
        guard let instance, settings.runtime != nil else { throw messages.runtimeMissing }
        return instance
    }

    private func begin(allowingRecovery: Bool) throws {
        guard !busy else { throw JerdError.unavailable(messages.busy) }
        guard allowingRecovery || !transaction.isPending else { throw messages.updatePending }
        busy = true
    }

    func makeInstance(runtime: Runtime, ports: Ports) -> ManagedInstance {
        ManagedInstance(definition: service.definition(runtime: runtime, ports: ports), effects: effects)
    }

    func setInstance(_ next: ManagedInstance) { instance = next }

    /// Restores an unfinished runtime update. Without a journal it does nothing.
    func recoverPendingUpdate() async throws {
        guard transaction.isPending else { return }
        guard let instance else { throw messages.recoveryWithoutRuntime }
        try await transaction.recoverIfNeeded(on: instance, reload: { try await self.reloadDefinition() })
    }

    /// Reloads the saved settings, for example after a restore, and returns their definition.
    func reloadDefinition() throws -> any ServiceDefinition {
        let restored = try service.loadSettings()
        guard let runtime = restored.runtime else { throw messages.recoveryWithoutRuntime }
        settings = restored
        return service.definition(runtime: runtime, ports: restored.ports)
    }
}
