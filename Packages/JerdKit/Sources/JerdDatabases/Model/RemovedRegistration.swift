/// The registration kept in `instances/<UUID>/removed-registration.json` after Remove, so that
/// Restore can register the data again under its original ID, name, port, and runtime.
package struct RemovedRegistration: Codable, Equatable, Sendable {
    package static let supportedVersion = 1

    package let schemaVersion: Int
    package let service: DatabaseService
    package let runtime: DatabaseRuntime

    package init(service: DatabaseService, runtime: DatabaseRuntime) {
        schemaVersion = Self.supportedVersion
        self.service = service
        self.runtime = runtime
    }

    /// A supported version, and a service that names this runtime.
    package var isValid: Bool {
        schemaVersion == Self.supportedVersion && service.runtimeID == runtime.id
    }
}
