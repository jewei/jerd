import JerdStorage

/// The local RustFS service and its buckets. JerdLive implements it with `StorageManager`; the
/// live `load()` first installs the bundled RustFS when no runtime is saved.
public protocol StoragePort: Sendable {
    /// Reads `storage/settings.json` once and returns the first snapshot.
    /// - Throws: when the settings cannot be read. The file stays as it is.
    func load() async throws -> StorageSnapshot
    /// The settings, the state, and the listed buckets. It also detects an unexpected exit.
    func snapshot() async -> StorageSnapshot
    /// The data folder and the server log.
    func files() async -> ServiceFiles
    func start() async throws
    /// Stops gracefully. Buckets, objects, and credentials stay. A timeout leaves it `stuck`.
    func stop() async throws
    /// Saves a private or public-read bucket, starts storage when needed, and verifies it.
    func addBucket(name: String, publicRead: Bool) async throws
    /// Continues the setup of an unfinished bucket.
    func retryBucket(_ name: String) async throws
    /// Lists the buckets of the running service again.
    func refreshBuckets() async throws
    /// The saved access key and secret key. It reads only.
    func credentials() async throws -> StorageCredentials
    /// The first free S3 port from 9000 and the first other free console port from 9001.
    func suggestedPorts() async throws -> StoragePorts
    /// Moves stopped storage to two other free ports.
    func edit(ports: StoragePorts) async throws
}
