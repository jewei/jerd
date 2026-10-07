import Foundation
import JerdDatabases
import JerdMail
import JerdManifest
import JerdRuntimes
import JerdStorage
import os

/// Installs the embedded payloads of the data services (today Redis and Mailpit; MySQL,
/// PostgreSQL, and RustFS install on demand) with `BundledRuntimeBootstrap` and maps them to
/// service runtime records.
package struct BundledServiceRuntimes: ServiceRuntimeSource {
    /// Bundled setup failures do not fail a service load, so they go to the unified log, where
    /// `log show --predicate 'subsystem == "dev.jerd.app"'` finds them.
    static let log = Logger(subsystem: "dev.jerd.app", category: "bundled-runtimes")

    let bootstrap: BundledRuntimeBootstrap

    package init(bootstrap: BundledRuntimeBootstrap) {
        self.bootstrap = bootstrap
    }

    package func databaseRuntimes(excluding: Set<RuntimeKind>) async throws -> [DatabaseRuntime] {
        try await bootstrap.installDatabases(excluding: excluding).map(BundledRuntimeMapping.database)
    }

    package func mailRuntime() async throws -> MailRuntime {
        try BundledRuntimeMapping.mail(try await bootstrap.installMail())
    }

    package func storageRuntime() async throws -> StorageRuntime? {
        try await bootstrap.installStorage().map(BundledRuntimeMapping.storage)
    }

    /// Records a failed bundled setup. The service keeps the runtimes it has.
    static func report(_ error: any Error, service: String) {
        log.error(
            "Bundled \(service, privacy: .public) runtime setup failed: \(message(for: error), privacy: .public)")
    }

    /// The user message of a failed setup, which the service page shows.
    static func message(for error: any Error) -> String {
        if let description = (error as? any LocalizedError)?.errorDescription, !description.isEmpty {
            return description
        }
        return error.localizedDescription
    }
}
