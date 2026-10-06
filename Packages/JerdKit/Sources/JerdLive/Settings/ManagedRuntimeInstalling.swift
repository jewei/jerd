import JerdRuntimes

/// Installs and lists managed builds in `runtime-updates/`. `RuntimeInstaller` is the live type.
package protocol ManagedRuntimeInstalling: Sendable {
    func list() async -> [ManagedRuntimeListing]
    /// Removes staging folders that a crash left. Does nothing while an installation runs.
    func removeAbandonedStaging() async -> [String]
    func install(
        _ release: RuntimeRelease, tools: PreparationTools,
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> ManagedRuntime
}

extension RuntimeInstaller: ManagedRuntimeInstalling {}
