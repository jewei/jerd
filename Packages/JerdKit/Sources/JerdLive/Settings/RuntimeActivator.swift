import Foundation
import JerdDatabases
import JerdFoundation
import JerdMail
import JerdRuntimes
import JerdStorage
import JerdWeb

/// Puts an installed managed build into use with its owner (spec D U7). PHP and Caddy go
/// through the site change transaction; every other kind goes to its service owner.
package struct RuntimeActivator: Sendable {
    let owners: any RuntimeOwning
    let sites: any SiteChangeApplying
    let inspector: any ExecutableInspecting

    package init(owners: any RuntimeOwning, sites: any SiteChangeApplying, inspector: any ExecutableInspecting) {
        self.owners = owners
        self.sites = sites
        self.inspector = inspector
    }

    package func activate(_ build: ManagedRuntime, useAsDefault: Bool) async throws {
        switch build.kind {
        case .php: try await activatePHP(build, useAsDefault: useAsDefault)
        case .caddy:
            _ = try await commit(.caddy(try await inspector.inspectCaddy(build.executable)))
        case .mysql, .postgresql, .redis:
            try await owners.registerDatabaseRuntime(try Self.databaseRuntime(build))
        case .mailpit: try await owners.updateMailRuntime(Self.mailRuntime(build))
        case .rustfs: try await owners.updateStorageRuntime(Self.storageRuntime(build))
        case .cloudflared: try await owners.useTunnelRuntime(at: build.executable)
        case .composer, .laravel: try await owners.activateCompanion(build)
        }
    }

    /// Registers the build (the reducer keeps the ID of a record with the same paths), then
    /// makes that record the default when asked.
    private func activatePHP(_ build: ManagedRuntime, useAsDefault: Bool) async throws {
        guard let fpm = build.secondaryExecutable else {
            throw JerdError.invalid("The PHP-FPM executable is missing.")
        }
        let inspected = try await inspector.inspectPHP(cli: build.executable, fpm: fpm)
        let saved = try await commit(.upsertRuntime(inspected))
        guard useAsDefault else { return }
        guard let record = saved.runtimes.first(where: { $0.cliPath == inspected.cliPath }) else {
            throw JerdError.unavailable("The installed PHP runtime is not registered. Install it again.")
        }
        if saved.defaultRuntimeID != record.id {
            _ = try await commit(.defaultRuntime(record.id))
        }
    }

    private func commit(_ change: SiteChange) async throws -> AppConfiguration {
        try SiteChangeCommit.require(try await sites.apply(change, startIfStopped: false))
    }

    /// The database record of a build. Its folder name is the runtime ID.
    package static func databaseRuntime(_ build: ManagedRuntime) throws -> DatabaseRuntime {
        guard let engine = DatabaseEngine(rawValue: build.kind.rawValue) else {
            throw JerdError.invalid("This runtime is not a database runtime.")
        }
        return DatabaseRuntime(
            id: build.folderName, engine: engine, version: build.version, path: build.directory.path)
    }

    package static func mailRuntime(_ build: ManagedRuntime) -> MailRuntime {
        MailRuntime(id: build.folderName, version: build.version, path: build.directory.path)
    }

    package static func storageRuntime(_ build: ManagedRuntime) -> StorageRuntime {
        StorageRuntime(id: build.folderName, version: build.version, path: build.directory.path)
    }
}
