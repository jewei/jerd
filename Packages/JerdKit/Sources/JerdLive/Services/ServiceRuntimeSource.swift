import JerdDatabases
import JerdMail
import JerdManifest
import JerdStorage

/// The bundled runtimes of the data services, installed on first use. `BundledServiceRuntimes`
/// is the live type.
package protocol ServiceRuntimeSource: Sendable {
    /// Installs the bundled database runtimes, except the kinds in `excluding`.
    func databaseRuntimes(excluding: Set<RuntimeKind>) async throws -> [DatabaseRuntime]
    /// The embedded Mailpit, or nil when the app installs Mailpit on demand.
    func mailRuntime() async throws -> MailRuntime?
    /// The embedded RustFS, or nil when the app installs RustFS on demand.
    func storageRuntime() async throws -> StorageRuntime?
}
