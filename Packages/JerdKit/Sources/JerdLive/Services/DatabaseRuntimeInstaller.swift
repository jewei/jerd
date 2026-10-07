import Foundation
import JerdDatabases
import JerdFoundation
import JerdRuntimes
import JerdUI
import os

/// Installs the pinned runtime of a database engine on demand, then registers it.
///
/// It adds no pipeline of its own: the release comes from the reviewed pin in the app bundle, and
/// `OnDemandInstallFlow` reuses an earlier copy or lets the one `RuntimeInstaller` of the app
/// download, verify, prepare, and install it in `runtime-updates/`, as for every managed update. So
/// the size, the SHA-256, the MySQL signature, and the preparation steps are exactly those of
/// `./dev runtimes prepare`. The build gets a new runtime ID, so no existing database folder ever
/// changes its runtime. The Databases page and Runtimes both install through it.
package struct DatabaseRuntimeInstaller: Sendable {
    static let log = Logger(subsystem: "dev.jerd.app", category: "database-runtimes")

    let flow: OnDemandInstallFlow
    let manager: any DatabaseManaging

    package init(flow: OnDemandInstallFlow, manager: any DatabaseManaging) {
        self.flow = flow
        self.manager = manager
    }

    package init(
        releases: any OnDemandRuntimeProviding, installer: any ManagedRuntimeInstalling, manager: any DatabaseManaging,
        layout: DataLayout, freeSpace: any FreeSpaceReading = VolumeFreeSpace()
    ) {
        self.init(
            flow: OnDemandInstallFlow(releases: releases, installer: installer, layout: layout, freeSpace: freeSpace),
            manager: manager)
    }

    /// The database engines of the pinned on-demand releases, and whether each one reuses a copy on
    /// this Mac. A missing or bad catalog offers nothing and is logged; the page then leads to Runtimes.
    package func offers() async -> [DatabaseRuntimeOffer] {
        let releases: [RuntimeRelease]
        do {
            releases = try flow.releases.releases()
        } catch {
            Self.log.error(
                "Database runtimes cannot be offered: \(BundledServiceRuntimes.message(for: error), privacy: .public)")
            return []
        }
        var offers: [DatabaseRuntimeOffer] = []
        for release in releases {
            let reuses = await flow.reusesInstalledCopy(release)
            if let offer = Self.offer(release, reusesInstalledCopy: reuses) { offers.append(offer) }
        }
        return offers
    }

    /// Installs and registers the pinned runtime of `engine` through the one flow.
    package func install(
        _ engine: DatabaseEngine, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> DatabaseRuntime {
        let kind = BundledRuntimeMapping.kind(of: engine)
        guard let release = try flow.release(of: kind) else {
            throw JerdError.unavailable("This copy of Jerd cannot install \(engine.title). Install it in Runtimes.")
        }
        return try await install(release, progress: progress)
    }

    /// Installs and registers a pinned database release, also for Runtimes › Install….
    package func install(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> DatabaseRuntime {
        guard let engine = BundledRuntimeMapping.engine(of: release.kind) else {
            throw JerdError.invalid("\(release.kind.title) is not a database runtime.")
        }
        let runtime: DatabaseRuntime
        switch try await flow.install(release, progress: progress) {
        case .reused(let payload):
            runtime = DatabaseRuntime(
                id: payload.id, engine: engine, version: payload.version, path: payload.directory.path)
        case .built(let build):
            runtime = try RuntimeActivator.databaseRuntime(build)
        }
        try await manager.registerRuntimes([runtime])
        return runtime
    }

    /// The offer of a pinned database release; nil for another kind or a release without an
    /// exact size.
    package static func offer(_ release: RuntimeRelease, reusesInstalledCopy: Bool = false) -> DatabaseRuntimeOffer? {
        guard let engine = BundledRuntimeMapping.engine(of: release.kind), let size = release.downloadSize,
            let host = release.artifact.downloadURL?.host
        else { return nil }
        return DatabaseRuntimeOffer(
            engine: engine, versionLabel: release.versionLabel, downloadSize: size, source: host,
            installedSize: release.installedSize, isSigned: release.pinnedSignature != nil,
            reusesInstalledCopy: reusesInstalledCopy)
    }
}
