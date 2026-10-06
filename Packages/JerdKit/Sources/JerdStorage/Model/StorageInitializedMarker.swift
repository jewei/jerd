/// The content of `storage/initialized.json`: the runtime of the last successful start and the
/// SHA-256 (lowercase hexadecimal) of the RustFS volume format file and of `credentials.json`.
///
/// A later start requires all three to match, so changed data, changed credentials, or another
/// runtime is never opened.
public struct StorageInitializedMarker: Codable, Equatable, Sendable {
    public let runtime: StorageRuntime
    public let formatHash: String
    public let credentialsHash: String

    public init(runtime: StorageRuntime, formatHash: String, credentialsHash: String) {
        self.runtime = runtime
        self.formatHash = formatHash
        self.credentialsHash = credentialsHash
    }
}
