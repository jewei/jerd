import JerdStorage

/// The storage manager calls that the live ports use. `StorageManager` is the live type.
package protocol StorageManaging: Sendable {
    func load() async throws -> StorageSettings
    func snapshot() async -> StorageSnapshot
    func registerRuntime(_ runtime: StorageRuntime) async throws
    func updateRuntime(_ runtime: StorageRuntime) async throws
    func start() async throws
    func stop() async throws
    func addBucket(name: String, publicRead: Bool) async throws
    func retryBucket(_ name: String) async throws
    func refreshBuckets() async throws
    func credentials() async throws -> StorageCredentials
    func suggestedPorts() async throws -> StoragePorts
    func edit(ports: StoragePorts) async throws
}

extension StorageManager: StorageManaging {}
