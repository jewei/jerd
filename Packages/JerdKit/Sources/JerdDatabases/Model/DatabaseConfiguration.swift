import Foundation

/// The database registry saved in `databases/services.json` (schema 1).
///
/// The keys `schemaVersion`, `runtimes`, and `services` are required on decode.
public struct DatabaseConfiguration: Codable, Equatable, Sendable {
    public static let supportedVersion = 1
    /// The most runtimes and the most services.
    public static let recordLimit = 100

    public var schemaVersion: Int
    public var runtimes: [DatabaseRuntime]
    public var services: [DatabaseService]

    public init(
        schemaVersion: Int = supportedVersion, runtimes: [DatabaseRuntime] = [], services: [DatabaseService] = []
    ) {
        self.schemaVersion = schemaVersion
        self.runtimes = runtimes
        self.services = services
    }

    /// The runtime of `service`.
    /// - Throws: `.unavailable` when the runtime is not registered.
    public func runtime(for service: DatabaseService) throws -> DatabaseRuntime {
        guard let runtime = runtimes.first(where: { $0.id == service.runtimeID }) else {
            throw DatabaseMessages.runtimeUnavailable
        }
        return runtime
    }

    /// The registered service with `id`, or nil.
    public func service(_ id: UUID) -> DatabaseService? {
        services.first { $0.id == id }
    }
}
