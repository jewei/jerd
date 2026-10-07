import JerdManifest
import JerdRuntimes
import JerdUI

extension LiveRuntimeInventory {
    /// A pinned on-demand release goes through the one on-demand flow of its service page: reuse of
    /// an earlier copy, the free-space check, the install, and the registration. Nil for any other
    /// release, which installs as a managed update.
    func installOnDemand(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> InstalledBuild? {
        let version: String
        if let databases, BundledRuntimeMapping.engine(of: release.kind) != nil, databases.flow.isOnDemand(release) {
            version = try await databases.install(release, progress: progress).version
        } else if let storage, release.kind == .rustfs, storage.flow.isOnDemand(release) {
            version = try await storage.install(release, progress: progress).version
        } else {
            return nil
        }
        return InstalledBuild(
            kind: release.kind, version: version, releaseVersion: release.version,
            archiveSHA256: release.archiveSHA256 ?? "")
    }

    /// True when the on-demand flow already registered `build` (a reused earlier payload has no
    /// managed build), so activation has nothing left to do.
    func isRegisteredOnDemand(_ build: InstalledBuild) async throws -> Bool {
        if build.kind == .rustfs {
            guard storage != nil else { return false }
            return try await owners.records().storage?.version == build.version
        }
        guard databases != nil, let engine = BundledRuntimeMapping.engine(of: build.kind) else { return false }
        return try await owners.records().databases.contains { $0.engine == engine && $0.version == build.version }
    }
}
