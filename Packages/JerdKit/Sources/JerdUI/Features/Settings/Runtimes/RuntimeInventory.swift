import Foundation
import JerdManifest
import JerdRuntimes

/// The runtime operations of the Runtimes page. JerdLive implements it with `RuntimeCatalog`,
/// `RuntimeInstaller`, and the activation of each owner (sites, databases, mail, storage,
/// tunnels, CLI tools). Every method runs off the main actor.
public protocol RuntimeInventory: Sendable {
    /// The installed and active runtimes.
    func snapshot() async throws -> RuntimeInventorySnapshot
    /// Reads the publisher catalog of one kind. Failures are data in the result.
    func check(_ kind: RuntimeKind) async -> RuntimeUpdateCheck
    /// Downloads, verifies, and installs a release. Honors cancellation until the final rename.
    func install(
        _ release: RuntimeRelease, progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> InstalledBuild
    /// Puts an installed build into use. It is not cancellable: once started, it finishes.
    /// - Parameter useAsDefault: For PHP, also makes the build the default runtime.
    func activate(_ build: InstalledBuild, useAsDefault: Bool) async throws
}
