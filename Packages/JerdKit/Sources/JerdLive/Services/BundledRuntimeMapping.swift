import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdStorage

/// Pure mappings from installed bundled payloads to the runtime records of the services. The
/// folder name is the runtime ID and the folder is the runtime path, as older builds saved them.
package enum BundledRuntimeMapping {
    /// The database engine of a runtime kind, or nil for other kinds.
    package static func engine(of kind: RuntimeKind) -> DatabaseEngine? {
        switch kind {
        case .mysql: .mysql
        case .postgresql: .postgresql
        case .redis: .redis
        case .php, .caddy, .composer, .laravel, .mailpit, .rustfs, .cloudflared: nil
        }
    }

    /// The runtime kind of a database engine.
    package static func kind(of engine: DatabaseEngine) -> RuntimeKind {
        switch engine {
        case .mysql: .mysql
        case .postgresql: .postgresql
        case .redis: .redis
        }
    }

    /// The engines that already have a registered runtime. The bootstrap skips them, so a newer
    /// app never adds a second runtime of an engine on its own.
    package static func registeredKinds(_ configuration: DatabaseConfiguration) -> Set<RuntimeKind> {
        Set(configuration.runtimes.map { kind(of: $0.engine) })
    }

    package static func database(_ payload: InstalledPayload) throws -> DatabaseRuntime {
        guard let engine = engine(of: payload.kind) else {
            throw JerdError.invalid("The bundled \(payload.kind.title) payload is not a database runtime.")
        }
        return DatabaseRuntime(id: payload.id, engine: engine, version: payload.version, path: payload.directory.path)
    }

    package static func mail(_ payload: InstalledPayload) throws -> MailRuntime {
        guard payload.kind == .mailpit else {
            throw JerdError.invalid("The bundled \(payload.kind.title) payload is not Mailpit.")
        }
        return MailRuntime(id: payload.id, version: payload.version, path: payload.directory.path)
    }

    package static func storage(_ payload: InstalledPayload) throws -> StorageRuntime {
        guard payload.kind == .rustfs else {
            throw JerdError.invalid("The bundled \(payload.kind.title) payload is not RustFS.")
        }
        return StorageRuntime(id: payload.id, version: payload.version, path: payload.directory.path)
    }
}
