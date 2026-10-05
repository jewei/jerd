import Foundation
import JerdFoundation
import JerdServiceKit

/// The only reader and writer of `databases/services.json`, and the pure rules of registry changes.
///
/// Rules:
/// - A missing file loads as an empty registry and is not written.
/// - A corrupt or unsupported file is never replaced; its bytes stay for inspection.
/// - A save copies the saved bytes to `services.previous.json` first.
/// - A service never changes its runtime, and an installed runtime never changes under its ID.
/// - A port that another registered service uses is a port conflict, not corrupt settings.
struct DatabaseRegistry: Sendable {
    /// The largest `services.json`.
    static let sizeLimit = 1_048_576

    let store: ServiceSettingsStore<DatabaseConfiguration>

    init(layout: DatabasesLayout) {
        store = ServiceSettingsStore(
            file: layout.servicesFile, previousFile: layout.previousServicesFile, sizeLimit: Self.sizeLimit,
            name: "database settings", validate: { try $0.validate() },
            admit: { saved, new in
                try new.validateForSave()
                if let saved { try Self.requireStableRecords(saved: saved, new: new) }
            })
    }

    func load() throws -> DatabaseConfiguration {
        try store.load(orDefault: DatabaseConfiguration())
    }

    func save(_ configuration: DatabaseConfiguration) throws {
        try store.save(configuration)
    }

    /// Existing services keep their runtime, and existing runtimes keep every field.
    static func requireStableRecords(saved: DatabaseConfiguration, new: DatabaseConfiguration) throws {
        for service in new.services {
            if let old = saved.service(service.id), old.runtimeID != service.runtimeID {
                throw DatabaseMessages.reassignedRuntime
            }
        }
        for runtime in new.runtimes {
            if let old = saved.runtimes.first(where: { $0.id == runtime.id }), old != runtime {
                throw DatabaseMessages.replacedRuntime
            }
        }
    }
}
