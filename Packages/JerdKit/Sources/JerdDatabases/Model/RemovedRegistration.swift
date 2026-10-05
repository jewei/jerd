/// The registration kept in `instances/<UUID>/removed-registration.json` after Remove, so that
/// Restore can register the data again under its original ID, name, port, and runtime.
public struct RemovedRegistration: Codable, Equatable, Sendable {
    public static let supportedVersion = 1

    public let schemaVersion: Int
    public let service: DatabaseService
    public let runtime: DatabaseRuntime

    public init(service: DatabaseService, runtime: DatabaseRuntime) {
        schemaVersion = Self.supportedVersion
        self.service = service
        self.runtime = runtime
    }

    /// A supported version, and a service that names this runtime.
    public var isValid: Bool {
        schemaVersion == Self.supportedVersion && service.runtimeID == runtime.id
    }
}
