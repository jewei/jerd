/// The content of `storage/initialized.json`: the runtime of the last successful start and the
/// SHA-256 (lowercase hexadecimal) of the RustFS volume format file and of `credentials.json`.
///
/// A later start requires all three to match, so changed data, changed credentials, or another
/// runtime is never opened.
struct StorageInitializedMarker: Codable, Equatable, Sendable {
    let runtime: StorageRuntime
    let formatHash: String
    let credentialsHash: String
}
