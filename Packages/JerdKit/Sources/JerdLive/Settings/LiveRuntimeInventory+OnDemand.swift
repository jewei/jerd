import JerdManifest
import JerdRuntimes
import JerdUI

extension LiveRuntimeInventory {
    /// A pinned database release goes through the one on-demand flow of the Databases page: reuse
    /// of an earlier copy, the free-space check, the install, and the registration. Nil for any
    /// other release, which installs as a managed update.
    func installOnDemand(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> InstalledBuild? {
        guard let databases, BundledRuntimeMapping.engine(of: release.kind) != nil,
            databases.flow.isOnDemand(release)
        else { return nil }
        let runtime = try await databases.install(release, progress: progress)
        return InstalledBuild(
            kind: release.kind, version: runtime.version, releaseVersion: release.version,
            archiveSHA256: release.archiveSHA256 ?? "")
    }

    /// True when the on-demand flow already registered `build` (a reused earlier payload has no
    /// managed build), so activation has nothing left to do.
    func isRegisteredOnDemand(_ build: InstalledBuild) async throws -> Bool {
        guard databases != nil, let engine = BundledRuntimeMapping.engine(of: build.kind) else { return false }
        return try await owners.records().databases.contains { $0.engine == engine && $0.version == build.version }
    }
}
