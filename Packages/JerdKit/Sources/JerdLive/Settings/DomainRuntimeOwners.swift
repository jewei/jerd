import Foundation
import JerdDatabases
import JerdMail
import JerdRuntimes
import JerdStorage
import JerdTunnels

/// The live runtime owners: the domain managers of one app run. An actor, because the CLI
/// tools record is read and written with blocking file calls.
package actor DomainRuntimeOwners: RuntimeOwning {
    let domain: LiveDomain
    let companions: CLICompanionStore

    package init(domain: LiveDomain) {
        self.domain = domain
        companions = CLICompanionStore(layout: domain.layout)
    }

    package func records() async throws -> RuntimeRecords {
        RuntimeRecords(
            sites: try await domain.developmentRuntimes.loadConfiguration(),
            databases: await domain.databases.snapshot().configuration.runtimes,
            mail: await domain.mail.snapshot().settings.runtime,
            storage: await domain.storage.snapshot().settings.runtime,
            tunnel: await domain.tunnels.currentConfiguration().runtime, companions: try companions.load())
    }

    package func bundledLZMA() async throws -> SupportLibrary? {
        try await domain.bootstrap.bundledLZMA()
    }

    package func registerDatabaseRuntime(_ runtime: DatabaseRuntime) async throws {
        try await domain.databases.registerRuntime(runtime)
    }

    /// Registers the build when no Mailpit is saved, else updates the saved one.
    package func updateMailRuntime(_ runtime: MailRuntime) async throws {
        try await MailRuntimeAdoption.adopt(runtime, manager: domain.mail)
    }

    /// Registers the build when no RustFS is saved, else updates the saved one.
    package func updateStorageRuntime(_ runtime: StorageRuntime) async throws {
        try await StorageRuntimeAdoption.adopt(runtime, manager: domain.storage)
    }

    package func useTunnelRuntime(at executable: URL) async throws {
        _ = try await domain.tunnels.useRuntime(at: executable)
    }

    package func activateCompanion(_ runtime: ManagedRuntime) async throws {
        _ = try companions.activate(runtime)
    }
}
