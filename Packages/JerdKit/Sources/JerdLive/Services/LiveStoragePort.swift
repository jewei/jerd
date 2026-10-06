import JerdFoundation
import JerdStorage
import JerdUI

/// The Storage port on the one `StorageManager`. Its load installs the bundled RustFS when no
/// runtime is saved; a failed bundled setup leaves the load usable.
package struct LiveStoragePort: StoragePort {
    let manager: any StorageManaging
    let runtimes: any ServiceRuntimeSource
    let layout: StorageLayout

    package init(manager: any StorageManaging, runtimes: any ServiceRuntimeSource, layout: StorageLayout) {
        self.manager = manager
        self.runtimes = runtimes
        self.layout = layout
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
            } catch {
                BundledServiceRuntimes.report(error, service: "storage")
            }
        }
        return await manager.snapshot()
    }

    package func snapshot() async -> StorageSnapshot {
        await manager.snapshot()
    }

    package func files() async -> ServiceFiles {
        ServiceFilesProbe.files(dataFolder: layout.dataDirectory, log: layout.logFile)
    }

    package func start() async throws {
        try await manager.start()
    }

    package func stop() async throws {
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
