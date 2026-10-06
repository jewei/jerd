import Foundation
import JerdDatabases

/// The registered MySQL, PostgreSQL, and Redis services. JerdLive implements it with
/// `DatabaseManager`; the live `load()` first installs the bundled runtimes of missing engines.
public protocol DatabasesPort: Sendable {
    /// Reads `databases/services.json` once and returns the first snapshot.
    /// - Throws: when the settings cannot be read. The file stays as it is.
    func load() async throws -> DatabaseSnapshot
    /// The registry and every state. It also detects unexpected exits.
    func snapshot() async -> DatabaseSnapshot
    /// The data folder and the server log of one service.
    func files(for id: UUID) async -> ServiceFiles
    /// The first free port from the engine default that no registered service uses.
    func suggestedPort(for engine: DatabaseEngine) async throws -> UInt16
    /// Registers a new service. It does not start it.
    func add(name: String, runtimeID: String, port: UInt16) async throws -> DatabaseService
    /// Renames a stopped service or moves it to another free port.
    func edit(_ service: DatabaseService) async throws
    /// Stops the service and removes its registration. Every data file stays.
    func remove(_ id: UUID) async throws
    func start(_ id: UUID) async throws
    /// Stops gracefully. A timeout leaves the service `stuck`.
    func stop(_ id: UUID) async throws
    /// Stops every service for Quit. Any failure cancels Quit.
    func stopAll() async throws
    /// The Laravel connection of a service that started once.
    func connection(for id: UUID) async throws -> DatabaseConnection
    /// The data folders without a registration.
    func retainedDatabases() async throws -> [RetainedDatabase]
    /// Registers retained data again under its original ID and runtime.
    func restoreRegistration(_ id: UUID, name: String, port: UInt16) async throws -> DatabaseService
}
