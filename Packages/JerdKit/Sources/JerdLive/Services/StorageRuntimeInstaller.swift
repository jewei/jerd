import Foundation
import JerdFoundation
import JerdManifest
import JerdRuntimes
import JerdStorage
import JerdUI
import os

/// Installs the pinned RustFS on demand, then registers it with the storage manager.
///
/// It adds no pipeline of its own: `OnDemandInstallFlow` reuses an earlier copy or lets the one
/// `RuntimeInstaller` of the app download, verify, prepare, and install the pin in
/// `runtime-updates/`, as for the database engines. The preparation gets the app's own signed XZ
/// library (`LZMAProviding`), which `LZMALinker` copies into the installed runtime, so RustFS never
/// needs Homebrew. Registration only adds the runtime record: buckets, objects, and credentials are
/// never read or changed, and an existing runtime record is never replaced.
package struct StorageRuntimeInstaller: Sendable {
    static let log = Logger(subsystem: "dev.jerd.app", category: "storage-runtimes")

    let flow: OnDemandInstallFlow
    let manager: any StorageManaging
    let lzma: any LZMAProviding

    package init(flow: OnDemandInstallFlow, manager: any StorageManaging, lzma: any LZMAProviding) {
        self.flow = flow
        self.manager = manager
        self.lzma = lzma
    }

    /// The pinned RustFS, and whether its install reuses a copy on this Mac. A missing or bad
    /// catalog offers nothing and is logged; the page then leads to Runtimes.
    package func offer() async -> ServiceRuntimeOffer? {
        await flow.offer(of: .rustfs, log: Self.log)
    }

    /// Installs and registers the pinned RustFS through the one flow.
    package func install(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> StorageRuntime {
        guard let release = try flow.release(of: .rustfs) else {
            throw JerdError.unavailable("This copy of Jerd cannot install RustFS. Install it in Runtimes.")
        }
        return try await install(release, progress: progress)
    }

    /// Installs and registers the pinned RustFS release, also for Runtimes › Install….
    package func install(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> StorageRuntime {
        guard release.kind == .rustfs else { throw JerdError.invalid("\(release.kind.title) is not RustFS.") }
        let runtime: StorageRuntime
        switch try await flow.install(release, tools: { try await tools() }, progress: progress) {
        case .reused(let payload):
            runtime = StorageRuntime(id: payload.id, version: payload.version, path: payload.directory.path)
        case .built(let build):
            runtime = RuntimeActivator.storageRuntime(build)
        }
        try await manager.registerRuntime(runtime)
        return runtime
    }

    /// The XZ library of the app, checked before any download: without it the preparation of the
    /// upstream RustFS would fail only after the download.
    func tools() async throws -> PreparationTools {
        guard let library = try await lzma.bundledLZMA() else {
            throw JerdError.unavailable(
                "This copy of Jerd has no XZ library, so it cannot install RustFS. Use a release build of Jerd.")
        }
        return PreparationTools(lzma: library)
    }

    /// The offer of the pinned RustFS release; nil for another kind or a release without an exact size.
    package static func offer(_ release: RuntimeRelease, reusesInstalledCopy: Bool = false) -> ServiceRuntimeOffer? {
        OnDemandInstallFlow.offer(release, of: .rustfs, reusesInstalledCopy: reusesInstalledCopy)
    }
}

extension StorageRuntimeInstaller {
    /// The live installer: the pinned releases of the app bundle, its one `RuntimeInstaller`, the
    /// storage manager, and the XZ library of the bundle.
    package init(domain: LiveDomain) {
        self.init(
            flow: OnDemandInstallFlow(
                releases: domain.onDemandRuntimes, installer: domain.runtimeInstaller, layout: domain.layout),
            manager: domain.storage, lzma: domain.bootstrap)
    }
}
