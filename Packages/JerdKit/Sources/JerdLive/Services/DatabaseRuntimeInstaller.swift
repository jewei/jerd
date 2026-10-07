import Foundation
import JerdDatabases
import JerdFoundation
import JerdRuntimes
import JerdUI
import os

/// Installs the pinned runtime of a database engine on demand, then registers it.
///
/// It adds no pipeline of its own: the release comes from the reviewed pin in the app bundle, and
/// the one `RuntimeInstaller` of the app downloads, verifies, prepares, and installs it in
/// `runtime-updates/`, as for every managed update. So the size, the SHA-256, the MySQL signature,
/// and the preparation steps are exactly those of `./dev runtimes prepare`. The build gets a new
/// runtime ID, so no existing database folder ever changes its runtime.
package struct DatabaseRuntimeInstaller: Sendable {
    static let log = Logger(subsystem: "dev.jerd.app", category: "database-runtimes")

    let releases: any OnDemandRuntimeProviding
    let installer: any ManagedRuntimeInstalling
    let manager: any DatabaseManaging

    package init(
        releases: any OnDemandRuntimeProviding, installer: any ManagedRuntimeInstalling, manager: any DatabaseManaging
    ) {
        self.releases = releases
        self.installer = installer
        self.manager = manager
    }

    /// The database engines of the pinned on-demand releases. A missing or bad catalog offers
    /// nothing and is logged; the page then leads to Runtimes.
    package func offers() -> [DatabaseRuntimeOffer] {
        do {
            return try releases.releases().compactMap(Self.offer)
        } catch {
            Self.log.error(
                "Database runtimes cannot be offered: \(BundledServiceRuntimes.message(for: error), privacy: .public)")
            return []
        }
    }

    /// Installs and registers the pinned runtime of `engine`. An installed build of the same pin
    /// is verified and used again without a download.
    package func install(
        _ engine: DatabaseEngine, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> DatabaseRuntime {
        let kind = BundledRuntimeMapping.kind(of: engine)
        guard let release = try releases.releases().first(where: { $0.kind == kind }) else {
            throw JerdError.unavailable("This copy of Jerd cannot install \(engine.title). Install it in Runtimes.")
        }
        let build = try await installer.install(release, tools: PreparationTools(), progress: progress)
        let runtime = try RuntimeActivator.databaseRuntime(build)
        try await manager.registerRuntimes([runtime])
        return runtime
    }

    /// The offer of a pinned database release; nil for another kind or a release without an
    /// exact size.
    package static func offer(_ release: RuntimeRelease) -> DatabaseRuntimeOffer? {
        guard let engine = BundledRuntimeMapping.engine(of: release.kind), let size = release.downloadSize,
            let host = release.artifact.downloadURL?.host
        else { return nil }
        return DatabaseRuntimeOffer(
            engine: engine, versionLabel: release.versionLabel, downloadSize: size, source: host)
    }
}
