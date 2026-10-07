import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdUI

/// The `RuntimeInventory` of the Runtimes page: publisher catalogs, managed builds in
/// `runtime-updates/`, and activation by each runtime owner.
package struct LiveRuntimeInventory: RuntimeInventory {
    let catalog: any RuntimeCatalogChecking
    let installer: any ManagedRuntimeInstalling
    let owners: any RuntimeOwning
    let activator: RuntimeActivator
    /// The installation of the pinned database engines, shared with the Databases page, or nil.
    let databases: DatabaseRuntimeInstaller?

    package init(
        catalog: any RuntimeCatalogChecking, installer: any ManagedRuntimeInstalling, owners: any RuntimeOwning,
        activator: RuntimeActivator, databases: DatabaseRuntimeInstaller? = nil
    ) {
        self.catalog = catalog
        self.installer = installer
        self.owners = owners
        self.activator = activator
        self.databases = databases
    }

    /// The live inventory, on the app's one fetcher and installer. Every request of the
    /// catalog and the installer names the app version in its user agent.
    package init(domain: LiveDomain) {
        let owners = DomainRuntimeOwners(domain: domain)
        self.init(
            catalog: RuntimeCatalog(fetcher: domain.fetcher), installer: domain.runtimeInstaller, owners: owners,
            activator: RuntimeActivator(
                owners: owners, sites: domain.web.transaction, inspector: ExecutableInspector(layout: domain.layout)),
            databases: DatabaseRuntimeInstaller(
                releases: domain.onDemandRuntimes, installer: domain.runtimeInstaller, manager: domain.databases,
                layout: domain.layout))
    }

    /// Removes the staging folders of `runtime-updates/` that a crash left. The app calls it
    /// once at launch, before any installation can start.
    /// - Returns: The names of the removed folders.
    @discardableResult
    package func removeAbandonedStaging() async -> [String] {
        await installer.removeAbandonedStaging()
    }

    /// The installed runtimes and the pinned releases that the app installs on demand. A bad
    /// catalog in the bundle offers nothing; it never fails the page.
    package func snapshot() async throws -> RuntimeInventorySnapshot {
        let records = try await owners.records()
        var snapshot = records.snapshot(managed: await installer.list().compactMap(\.runtime))
        if let flow = databases?.flow {
            snapshot.onDemand = (try? flow.releases.releases()) ?? []
            for release in snapshot.onDemand where await flow.reusesInstalledCopy(release) {
                snapshot.reusableOnDemand.insert(release.kind)
            }
        }
        return snapshot
    }

    package func check(_ kind: RuntimeKind) async -> RuntimeUpdateCheck {
        await catalog.check(kind)
    }

    package func install(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> InstalledBuild {
        if let installed = try await installOnDemand(release, progress: progress) { return installed }
        let tools = try await tools(for: release.kind)
        let build = try await installer.install(release, tools: tools, progress: progress)
        return RuntimeRecords.installedBuild(build)
    }

    package func activate(_ build: InstalledBuild, useAsDefault: Bool) async throws {
        let managed = Self.managedRuntime(for: build, in: await installer.list())
        if managed == nil, try await isRegisteredOnDemand(build) { return }
        guard let managed else {
            throw JerdError.unavailable("The installed \(build.kind.title) build is missing. Install it again.")
        }
        try await activator.activate(managed, useAsDefault: useAsDefault)
    }

    /// Only the kinds that need a tool read it: Composer and the Laravel installer run with the
    /// default PHP (and Composer resolves the installer); RustFS gets the reviewed XZ library
    /// of the bundled payload instead of Homebrew's. Other kinds need nothing, so
    /// a corrupt site file never blocks a database or mail update.
    func tools(for kind: RuntimeKind) async throws -> PreparationTools {
        if kind.isPHPScript { return try await owners.records().preparationTools(lzma: nil) }
        if kind == .rustfs { return PreparationTools(lzma: try await owners.bundledLZMA()) }
        return PreparationTools()
    }

    /// The installed build that an `InstalledBuild` names: same kind, release, and digest.
    package static func managedRuntime(
        for build: InstalledBuild, in listing: [ManagedRuntimeListing]
    ) -> ManagedRuntime? {
        listing.lazy.compactMap(\.runtime).first {
            $0.kind == build.kind && $0.releaseVersion == build.releaseVersion
                && $0.archiveSHA256 == build.archiveSHA256
        }
    }
}
