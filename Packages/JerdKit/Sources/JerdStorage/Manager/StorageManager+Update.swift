import JerdFoundation
import JerdServiceKit

extension StorageManager {
    /// Replaces the RustFS runtime as a journaled transaction (see `RuntimeUpdateTransaction`).
    ///
    /// The data is first checked against the saved runtime without a write, so storage that
    /// never started gets no data or credentials here. Then the settings, the data, the markers,
    /// and the credentials are backed up off this actor (APFS clones when the volume supports
    /// them), the new runtime must pass a full start and list every complete bucket, and stopped
    /// storage is stopped again. A failure restores the backup and restarts the previous runtime
    /// when it ran. The backup stays until the user deletes it in Advanced.
    public func updateRuntime(_ runtime: StorageRuntime) async throws {
        try await exclusive {
            guard let previous = settings.runtime, let instance else { throw StorageMessages.runtimeMissing }
            guard runtime != previous else { return }
            guard runtime.isValid else { throw StorageMessages.runtimeRecordInvalid }
            var updated = settings
            updated.runtime = runtime
            let next = updated
            let data = StorageData(layout: layout)
            let steps = RuntimeUpdateSteps(
                validatePrevious: { try data.validate(for: previous) },
                apply: { try await self.adopt(next, replacing: previous) },
                verifyStarted: { try await self.requireCompleteBucketsListed() },
                reloadAfterRestore: { try await self.reloadDefinition() })
            let wasRunning = await instance.processID != nil
            do {
                try await transaction.run(
                    on: instance, to: definition(runtime: runtime, ports: next.ports), steps: steps)
            } catch {
                if !wasRunning { try await clearRestoredFailure(of: instance) }
                throw error
            }
        }
    }

    /// After a restore of a service that was stopped, the previous runtime is back and nothing
    /// runs, so the state is `stopped`. The error still names the cause. A failed restore keeps its
    /// journal and its `failed` state.
    private func clearRestoredFailure(of instance: ManagedInstance) async throws {
        guard !transaction.isPending, await instance.processID == nil else { return }
        try await instance.stop()
    }

    /// Saves `next` with its new runtime and moves the saved data markers to it.
    private func adopt(_ next: StorageSettings, replacing previous: StorageRuntime) throws {
        guard let runtime = next.runtime else { throw StorageMessages.runtimeMissing }
        try save(next, replacing: previous)
        try StorageData(layout: layout).adopt(runtime)
    }

    /// The updated service must list every complete bucket.
    private func requireCompleteBucketsListed() throws {
        let complete = Set(settings.buckets.filter(\.setupComplete).map(\.name))
        guard complete.isSubset(of: listed.current) else { throw StorageMessages.bucketsMissingAfterUpdate }
    }
}
