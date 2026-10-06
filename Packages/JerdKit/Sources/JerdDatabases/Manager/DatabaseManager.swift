import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// Owns the database registry and one independent `ManagedInstance` per registered service.
///
/// Rules:
/// - Every call except `load`, `snapshot`, and `stopAll` requires a loaded registry.
/// - Instances start and stop independently and in parallel. Each has its own lock and record.
/// - Edit, Remove, and Restore of one service exclude each other and its start and stop.
/// - Remove keeps every data file. Restore registers retained data again under its original ID.
/// - Exit detection in `snapshot()` never waits for a stop, and never blocks Quit.
public actor DatabaseManager {
    let layout: DatabasesLayout
    let effects: ServiceEffects
    let temporaryRoot: URL
    let registry: DatabaseRegistry
    var configuration = DatabaseConfiguration()
    var instances: [UUID: ManagedInstance] = [:]
    /// Services with an Edit, Remove, or Restore in progress.
    var operations: Set<UUID> = []
    var loaded = false

    /// - Parameters:
    ///   - layout: `<root>/databases`.
    ///   - temporaryRoot: where socket folders are made.
    ///
    /// `initdb` and `mysqld --initialize-insecure` run as owned processes of the instance through
    /// `effects`, so a timeout never kills them and never releases the lock.
    public init(
        layout: DatabasesLayout, effects: ServiceEffects, temporaryRoot: URL = FileManager.default.temporaryDirectory
    ) {
        self.layout = layout
        self.effects = effects
        self.temporaryRoot = temporaryRoot
        registry = DatabaseRegistry(layout: layout)
    }

    /// Loads the registry once and creates `databases/` (mode 0700). Later calls return the
    /// loaded registry.
    public func load() throws -> DatabaseConfiguration {
        guard !loaded else { return configuration }
        try OwnedDirectory.create(layout.root)
        configuration = try registry.load()
        loaded = true
        return configuration
    }

    /// Adds newly installed runtimes. A known ID must describe the same runtime.
    public func registerRuntimes(_ runtimes: [DatabaseRuntime]) throws {
        try requireLoaded()
        let next = try DatabaseRegistry.registering(runtimes, in: configuration)
        if next != configuration { try save(next) }
    }

    /// Adds one newly installed runtime, for example after a runtime update.
    public func registerRuntime(_ runtime: DatabaseRuntime) throws {
        try registerRuntimes([runtime])
    }

    /// The first free port from the engine default that no registered service uses.
    public func suggestedPort(for engine: DatabaseEngine) async throws -> UInt16 {
        try requireLoaded()
        return try await effects.ports.suggest(
            startingAt: engine.defaultPort, excluding: Set(configuration.services.map(\.port)))
    }

    /// The registry and the state of every service. It also detects unexpected exits.
    public func snapshot() async -> DatabaseSnapshot {
        var states: [UUID: ServiceState] = [:]
        for service in configuration.services {
            states[service.id] = await instances[service.id]?.refresh() ?? .stopped
        }
        return DatabaseSnapshot(configuration: configuration, states: states)
    }

    /// The Laravel connection settings of a service that started once.
    public func connection(for id: UUID) throws -> DatabaseConnection {
        let service = try lookup(id)
        let runtime = try configuration.runtime(for: service)
        let file = layout.instance(id).credentialsFile
        guard FileProbe.presence(at: file).mayExist else { throw DatabaseMessages.startOnce }
        let credentials = try DatabaseCredentials.read(from: file)
        return DatabaseConnection(engine: runtime.engine, port: service.port, password: credentials.password)
    }

    // MARK: Helpers

    func requireLoaded() throws {
        guard loaded else { throw DatabaseMessages.notLoaded }
    }

    func lookup(_ id: UUID) throws -> DatabaseService {
        try requireLoaded()
        guard let service = configuration.service(id) else { throw DatabaseMessages.notRegistered }
        return service
    }

    func save(_ next: DatabaseConfiguration) throws {
        try registry.save(next)
        configuration = next
    }

    func definition(for service: DatabaseService) throws -> DatabaseServiceDefinition {
        DatabaseServiceDefinition(
            service: service, runtime: try configuration.runtime(for: service), layout: layout,
            temporaryRoot: temporaryRoot)
    }

    /// The instance of `service`, created on first use.
    func instance(for service: DatabaseService) throws -> ManagedInstance {
        if let instance = instances[service.id] { return instance }
        let instance = ManagedInstance(definition: try definition(for: service), effects: effects)
        instances[service.id] = instance
        return instance
    }

    func begin(_ id: UUID) throws {
        guard operations.insert(id).inserted else { throw JerdError.unavailable(DatabaseMessages.busy) }
    }
}
