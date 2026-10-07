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
    /// The data root: where earlier payloads may wait for reuse, and whose volume must have room.
    let layout: DataLayout
    let freeSpace: any FreeSpaceReading

    package init(
        releases: any OnDemandRuntimeProviding, installer: any ManagedRuntimeInstalling, manager: any DatabaseManaging,
        layout: DataLayout, freeSpace: any FreeSpaceReading = VolumeFreeSpace()
    ) {
        self.releases = releases
        self.installer = installer
        self.manager = manager
        self.layout = layout
        self.freeSpace = freeSpace
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

    /// Installs and registers the pinned runtime of `engine`. A verified payload of the same pin
    /// that an earlier copy installed, and an installed build of the same pin, are used again
    /// without a download. A volume without room for the download and the installed copy stops it
    /// before the download.
    package func install(
        _ engine: DatabaseEngine, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> DatabaseRuntime {
        let kind = BundledRuntimeMapping.kind(of: engine)
        guard let release = try releases.releases().first(where: { $0.kind == kind }) else {
            throw JerdError.unavailable("This copy of Jerd cannot install \(engine.title). Install it in Runtimes.")
        }
        if let payload = try await releases.reusablePayload(for: kind, layout: layout) {
            let runtime = DatabaseRuntime(
                id: payload.id, engine: engine, version: payload.version, path: payload.directory.path)
            try await manager.registerRuntimes([runtime])
            progress(RuntimeInstallProgress("Using the installed \(release.title).", 1))
            return runtime
        }
        try checkFreeSpace(for: release)
        let build = try await installer.install(release, tools: PreparationTools(), progress: progress)
        let runtime = try RuntimeActivator.databaseRuntime(build)
        try await manager.registerRuntimes([runtime])
        return runtime
    }

    /// The download and the installed copy exist at the same time, so both must fit.
    func checkFreeSpace(for release: RuntimeRelease) throws {
        guard let required = release.requiredSpace,
            let available = freeSpace.availableBytes(near: layout.runtimes.managedRuntimesDirectory),
            available < required
        else { return }
        throw JerdError.unavailable(
            "Installing \(release.title) needs about \(ByteText.format(required)) of free disk space, and "
                + "\(ByteText.format(available)) is free. Free some space, then try again.")
    }

    /// The offer of a pinned database release; nil for another kind or a release without an
    /// exact size.
    package static func offer(_ release: RuntimeRelease) -> DatabaseRuntimeOffer? {
        guard let engine = BundledRuntimeMapping.engine(of: release.kind), let size = release.downloadSize,
            let host = release.artifact.downloadURL?.host
        else { return nil }
        return DatabaseRuntimeOffer(
            engine: engine, versionLabel: release.versionLabel, downloadSize: size, source: host,
            installedSize: release.installedSize, isSigned: release.pinnedSignature != nil)
    }
}
