import JerdStorage

/// Puts an installed RustFS build into use with the storage manager.
///
/// The app installs RustFS on demand, so a new user has no saved runtime. A build from Check for
/// Runtime Updates is then registered, the same way as the on-demand install: no data exists for
/// it, and `registerRuntime` never replaces a saved runtime. With a saved runtime the build goes
/// through the journaled update, which checks and backs up the data.
package enum StorageRuntimeAdoption {
    package static func adopt(_ runtime: StorageRuntime, manager: any StorageManaging) async throws {
        if await manager.snapshot().settings.runtime == nil {
            try await manager.registerRuntime(runtime)
        } else {
            try await manager.updateRuntime(runtime)
        }
    }
}
