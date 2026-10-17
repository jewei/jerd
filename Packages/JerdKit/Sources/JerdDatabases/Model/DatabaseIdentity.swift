import Foundation

/// The data identity saved in `instances/<UUID>/runtime.json` and `initialized.json`.
///
/// Data belongs to exactly one service and one runtime version. It is never opened with another.
package struct DatabaseIdentity: Codable, Equatable, Sendable {
    package let serviceID: UUID
    package let runtimeID: String
    package let engine: DatabaseEngine
    package let version: String

    package init(serviceID: UUID, runtimeID: String, engine: DatabaseEngine, version: String) {
        self.serviceID = serviceID
        self.runtimeID = runtimeID
        self.engine = engine
        self.version = version
    }

    /// The identity of `service` on `runtime`.
    package init(service: DatabaseService, runtime: DatabaseRuntime) {
        self.init(serviceID: service.id, runtimeID: runtime.id, engine: runtime.engine, version: runtime.version)
    }
}
