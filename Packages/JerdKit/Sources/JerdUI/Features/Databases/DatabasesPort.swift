import Foundation
import JerdDatabases
import JerdRuntimes

/// The registered MySQL, PostgreSQL, and Redis services. JerdLive implements it with
/// `DatabaseManager`; the live `load()` first installs the bundled runtimes of missing engines.
/// An app that does not embed the database runtimes installs each engine on demand.
public protocol DatabasesPort: Sendable {
    /// The engines that Jerd can download and install, from the reviewed pins of the app. Empty
    /// when the app carries no pins; it never touches the network.
    func runtimeOffers() async -> [DatabaseRuntimeOffer]
    /// Downloads, verifies, prepares, and installs the pinned runtime of `engine`, then registers
    /// it. A download that does not match its pin installs nothing. Cancellation stops it until
    /// the final rename; after that the runtime is installed and registered.
    func installRuntime(
        _ engine: DatabaseEngine, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> DatabaseRuntime
    /// Reads `databases/services.json` once and returns the first snapshot.
    /// - Throws: when the settings cannot be read. The file stays as it is.
    func load() async throws -> DatabaseSnapshot
    /// Why the setup of the bundled runtimes in the last `load()` failed, or nil. The load stays
    /// usable without them; the page shows this reason with the way to install them.
    func runtimeSetupFailure() async -> String?
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
