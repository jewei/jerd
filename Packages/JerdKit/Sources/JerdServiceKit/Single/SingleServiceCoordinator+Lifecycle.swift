import JerdFoundation

extension SingleServiceCoordinator {
    /// Recovers an unfinished runtime update, then starts the service. Errors keep the kind of
    /// the failed step.
    package func start() async throws {
        try await exclusive(allowingRecovery: true) { coordinator in
            let instance = try coordinator.requireInstance()
            try await coordinator.recoverPendingUpdate()
            try await instance.start()
        }
    }

    /// Stops the service gracefully, also while a runtime update needs recovery. The data stays.
    /// A stop that exit detection began is joined.
    package func stop() async throws {
        try await exclusive(allowingRecovery: true) { coordinator in
            try await coordinator.instance?.stop()
        }
    }

    /// Replaces the runtime as a journaled transaction (see `RuntimeUpdateTransaction`).
    ///
    /// The data is first checked against the saved runtime without a write. Then every update
    /// item is backed up, the new runtime must pass a full start and `verifyUpdatedService`, and
    /// a stopped service is stopped again. A failure restores the backup and restarts the
    /// previous runtime when it ran. The backup stays until the user deletes it in Advanced.
    package func updateRuntime(_ runtime: Runtime) async throws {
        try await exclusive { coordinator in
            let instance = try coordinator.requireInstance()
            guard let previous = coordinator.settings.runtime, runtime != previous else { return }
            guard runtime.isValid else { throw coordinator.messages.runtimeRecordInvalid }
            var updated = coordinator.settings
            updated.runtime = runtime
            let next = updated
            let service = coordinator.service
            let steps = RuntimeUpdateSteps(
                validatePrevious: { try service.validateData(for: previous) },
                apply: { try await self.adopt(next, replacing: previous) },
                verifyStarted: { try await service.verifyUpdatedService(next) },
                reloadAfterRestore: { try await self.reloadDefinition() })
            try await coordinator.transaction.run(
                on: instance, to: service.definition(runtime: runtime, ports: next.ports), steps: steps)
        }
    }

    /// Saves `next` with its new runtime and moves the saved data markers to it.
    private func adopt(_ next: Settings, replacing previous: Runtime) throws {
        guard let runtime = next.runtime else { throw messages.runtimeMissing }
        try save(next, replacing: previous)
        try service.adoptData(runtime)
    }
}
