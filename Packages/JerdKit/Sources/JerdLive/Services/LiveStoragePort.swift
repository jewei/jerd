import JerdFoundation
import JerdRuntimes
import JerdStorage
import JerdUI

/// The Storage port on the one `StorageManager`. Its load installs an embedded RustFS when no
/// runtime is saved; a failed bundled setup leaves the load usable. An app that does not embed
/// RustFS installs it on demand, only after a user action, and its load downloads nothing.
package struct LiveStoragePort: StoragePort {
    let manager: any StorageManaging
    let runtimes: any ServiceRuntimeSource
    let layout: StorageLayout
    let setup: BundledSetupRecord
    /// The on-demand installation, or nil in a port without one: it offers nothing then.
    let onDemand: StorageRuntimeInstaller?

    package init(
        manager: any StorageManaging, runtimes: any ServiceRuntimeSource, layout: StorageLayout,
        setup: BundledSetupRecord = BundledSetupRecord(), onDemand: StorageRuntimeInstaller? = nil
    ) {
        self.manager = manager
        self.runtimes = runtimes
        self.layout = layout
        self.setup = setup
        self.onDemand = onDemand
    }

    package init(domain: LiveDomain) {
        self.init(
            manager: domain.storage, runtimes: BundledServiceRuntimes(bootstrap: domain.bootstrap),
            layout: domain.layout.storage, onDemand: StorageRuntimeInstaller(domain: domain))
    }

    package func runtimeOffer() async -> ServiceRuntimeOffer? {
        await onDemand?.offer()
    }

    package func installRuntime(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> StorageRuntime {
        guard let onDemand else {
            throw JerdError.unavailable("This copy of Jerd cannot install RustFS. Install it in Runtimes.")
        }
        ServiceActivityLog.request("Install", "the RustFS runtime")
        return try await onDemand.install(progress: progress)
    }

    /// Loads the settings first: corrupt settings fail here and nothing is installed. A saved
    /// runtime (also one that an earlier copy installed in `storage-runtimes/`) stays in use.
    package func load() async throws -> StorageSnapshot {
        if try await manager.load().runtime == nil {
            do {
                if let embedded = try await runtimes.storageRuntime() {
                    try await manager.registerRuntime(embedded)
                }
                await setup.record(nil)
            } catch {
                BundledServiceRuntimes.report(error, service: "storage")
                await setup.record(BundledServiceRuntimes.message(for: error))
            }
        }
        return await manager.snapshot()
    }

    package func runtimeSetupFailure() async -> String? {
        await setup.failure
    }

    package func snapshot() async -> StorageSnapshot {
        await manager.snapshot()
    }

    package func files() async -> ServiceFiles {
        ServiceFilesProbe.files(dataFolder: layout.dataDirectory, log: layout.logFile)
    }

    package func start() async throws {
        ServiceActivityLog.request("Start", "storage")
        try await manager.start()
    }

    package func stop() async throws {
        ServiceActivityLog.request("Stop", "storage")
        try await manager.stop()
    }

    package func addBucket(name: String, publicRead: Bool) async throws {
        try await manager.addBucket(name: name, publicRead: publicRead)
    }

    package func retryBucket(_ name: String) async throws {
        try await manager.retryBucket(name)
    }

    package func refreshBuckets() async throws {
        try await manager.refreshBuckets()
    }

    /// Reads the saved keys only. It never creates or changes credentials.
    package func credentials() async throws -> StorageCredentials {
        try await manager.credentials()
    }

    package func suggestedPorts() async throws -> StoragePorts {
        try await manager.suggestedPorts()
    }

    package func edit(ports: StoragePorts) async throws {
        try await manager.edit(ports: ports)
    }
}
