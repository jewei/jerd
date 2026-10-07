import JerdRuntimes
import JerdStorage

/// The local RustFS service and its buckets. JerdLive implements it with `StorageManager`; the
/// live `load()` installs an embedded RustFS when no runtime is saved. An app that installs RustFS
/// on demand downloads nothing at load: `installRuntime` runs only after a user action.
public protocol StoragePort: Sendable {
    /// Reads `storage/settings.json` once and returns the first snapshot.
    /// - Throws: when the settings cannot be read. The file stays as it is.
    func load() async throws -> StorageSnapshot
    /// Why the setup of the bundled RustFS in the last `load()` failed, or nil. The load stays
    /// usable without it; the page shows this reason with the way to install it.
    func runtimeSetupFailure() async -> String?
    /// The pinned RustFS that Jerd can install on demand, or nil when the app has no such pin.
    func runtimeOffer() async -> StorageRuntimeOffer?
    /// Installs the pinned RustFS (reuse, free space, download, checks, preparation) and registers
    /// it. It never touches buckets, objects, or credentials. Cancellation stops it before its
    /// final rename.
    func installRuntime(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> StorageRuntime
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
