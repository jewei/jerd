import Foundation
import JerdDatabases
import JerdMail
import JerdRuntimes
import JerdStorage

/// The owners of runtime records outside the site configuration: databases, mail, storage,
/// tunnels, and the CLI tools record. `DomainRuntimeOwners` is the live type; tests record calls.
package protocol RuntimeOwning: Sendable {
    /// Every saved runtime record, including the site configuration.
    func records() async throws -> RuntimeRecords
    /// The reviewed XZ library of the bundled RustFS, or nil in builds without it.
    func bundledLZMA() async throws -> SupportLibrary?
    func registerDatabaseRuntime(_ runtime: DatabaseRuntime) async throws
    func updateMailRuntime(_ runtime: MailRuntime) async throws
    func updateStorageRuntime(_ runtime: StorageRuntime) async throws
    /// Checks the `cloudflared` executable and uses it for every tunnel.
    func useTunnelRuntime(at executable: URL) async throws
    /// Selects a managed Composer or Laravel installer build in the CLI tools record.
    func activateCompanion(_ runtime: ManagedRuntime) async throws
}
