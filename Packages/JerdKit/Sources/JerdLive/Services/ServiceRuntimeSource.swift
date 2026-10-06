import JerdDatabases
import JerdMail
import JerdManifest
import JerdStorage

/// The bundled runtimes of the data services, installed on first use. `BundledServiceRuntimes`
/// is the live type.
package protocol ServiceRuntimeSource: Sendable {
    /// Installs the bundled database runtimes, except the kinds in `excluding`.
    func databaseRuntimes(excluding: Set<RuntimeKind>) async throws -> [DatabaseRuntime]
    func mailRuntime() async throws -> MailRuntime
    func storageRuntime() async throws -> StorageRuntime
}
