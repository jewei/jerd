import Foundation

/// The content of `storage/settings.json`.
///
/// The synthesized `Codable` form is the compatibility contract: `schemaVersion`, `apiPort`,
/// `consolePort`, and `buckets` are required on decode, and `runtime` is left out while it is nil.
public struct StorageSettings: Codable, Equatable, Sendable {
    /// The only settings version that this build reads and writes.
    public static let supportedVersion = 1
    /// The default ports of new storage.
    public static let defaultPorts = StoragePorts(api: 9_000, console: 9_001)
    /// The most registered buckets.
    public static let bucketLimit = 1_000
    /// The S3 region of the local service.
    public static let region = "us-east-1"

    public var schemaVersion = StorageSettings.supportedVersion
    public var runtime: StorageRuntime?
    public var apiPort: UInt16 = StorageSettings.defaultPorts.api
    public var consolePort: UInt16 = StorageSettings.defaultPorts.console
    public var buckets: [StorageBucket] = []

    public init(runtime: StorageRuntime? = nil, ports: StoragePorts = defaultPorts, buckets: [StorageBucket] = []) {
        self.runtime = runtime
        apiPort = ports.api
        consolePort = ports.console
        self.buckets = buckets
    }

    /// The S3 API and console ports.
    public var ports: StoragePorts {
        get { StoragePorts(api: apiPort, console: consolePort) }
        set {
            apiPort = newValue.api
            consolePort = newValue.console
        }
    }

    /// The registered bucket with `name`.
    public func bucket(_ name: String) -> StorageBucket? { buckets.first { $0.name == name } }

    /// The path-style S3 endpoint: `http://127.0.0.1:<api>`.
    public var endpoint: String { "http://127.0.0.1:\(apiPort)" }

    /// The RustFS console page: `http://127.0.0.1:<console>/rustfs/console/`.
    public var consoleURL: URL {
        URL(string: "http://127.0.0.1:\(consolePort)/rustfs/console/") ?? URL(fileURLWithPath: "/")
    }

    /// The Laravel `.env` lines for one bucket. Each line ends with a newline.
    public func laravelEnvironment(bucket: StorageBucket, credentials: StorageCredentials) -> String {
        """
        FILESYSTEM_DISK=s3
        AWS_ACCESS_KEY_ID=\(credentials.accessKey)
        AWS_SECRET_ACCESS_KEY=\(credentials.secretKey)
        AWS_DEFAULT_REGION=\(Self.region)
        AWS_BUCKET=\(bucket.name)
        AWS_ENDPOINT=\(endpoint)
        AWS_URL=\(endpoint)/\(bucket.name)
        AWS_USE_PATH_STYLE_ENDPOINT=true

        """
    }

    /// The rules of every load and save: a supported version, two different ports from 1024, at
    /// most 1000 unique valid bucket names, and a valid runtime record.
    public func validate() throws {
        guard schemaVersion == Self.supportedVersion, ports.isValid, buckets.count <= Self.bucketLimit,
            Set(buckets.map(\.name)).count == buckets.count
        else { throw StorageMessages.settingsInvalid }
        for bucket in buckets { try BucketName.validate(bucket.name) }
        if let runtime, !runtime.isValid { throw StorageMessages.runtimeRecordInvalid }
    }
}
