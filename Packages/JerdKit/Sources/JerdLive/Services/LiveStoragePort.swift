import JerdFoundation
import JerdStorage
import JerdUI

/// The Storage port on the one `StorageManager`. Its load installs the bundled RustFS when no
/// runtime is saved; a failed bundled setup leaves the load usable.
package struct LiveStoragePort: StoragePort {
    let manager: any StorageManaging
    let runtimes: any ServiceRuntimeSource
    let layout: StorageLayout
    let setup: BundledSetupRecord

    package init(
        manager: any StorageManaging, runtimes: any ServiceRuntimeSource, layout: StorageLayout,
        setup: BundledSetupRecord = BundledSetupRecord()
    ) {
        self.manager = manager
        self.runtimes = runtimes
        self.layout = layout
        self.setup = setup
    }

    package init(domain: LiveDomain) {
        self.init(
            manager: domain.storage, runtimes: BundledServiceRuntimes(bootstrap: domain.bootstrap),
            layout: domain.layout.storage)
    }

    /// Loads the settings first: corrupt settings fail here and nothing is installed.
    package func load() async throws -> StorageSnapshot {
        if try await manager.load().runtime == nil {
            do {
                try await manager.registerRuntime(try await runtimes.storageRuntime())
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
