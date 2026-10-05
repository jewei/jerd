import JerdFoundation

extension RuntimeUpdateTransaction {
    /// Restores an unfinished update, for example after a crash. Without a journal it does nothing.
    ///
    /// - Parameter reload: reloads the restored settings and returns their definition.
    /// - Throws: `.unavailable(stopBeforeRecovery)` while a process is owned, or the restore error.
    public func recoverIfNeeded(
        on instance: ManagedInstance, reload: @Sendable () async throws -> any ServiceDefinition
    ) async throws {
        guard isPending else { return }
        guard await instance.processID == nil else { throw JerdError.unavailable(messages.stopBeforeRecovery) }
        let lease = try await instance.beginMaintenance()
        do {
            try await restore(holding: lease)
            try await instance.replaceDefinition(reload(), in: lease)
        } catch {
            await instance.endMaintenance(lease)
            throw error
        }
        await instance.endMaintenance(lease)
    }

    /// Undoes a failed update inside the lease and returns the error to report.
    func rollBack(
        after failure: any Error, backedUp: Bool, on instance: ManagedInstance, lease: MaintenanceLease,
        steps: RuntimeUpdateSteps
    ) async -> JerdError {
        let cause = FailureDetail.describe(failure)
        let previous: any ServiceDefinition
        do {
            try await instance.stop(in: lease)
            if backedUp { try await restore(holding: lease) }
            previous = try await steps.reloadAfterRestore()
            try await instance.replaceDefinition(previous, in: lease)
        } catch {
            let recovery = FailureDetail.describe(error)
            await instance.endMaintenance(
                lease, failure: "\(messages.service) update failed. \(cause) Recovery: \(recovery)")
            return .processFailed("\(messages.service) update failed. Backup files were preserved. \(recovery)")
        }
        var message =
            backedUp
            ? "\(messages.service) update failed. \(messages.restored) \(cause)"
            : "\(messages.service) update failed. Nothing was changed. \(cause)"
        if lease.wasRunning {
            do {
                try await instance.start(in: lease, with: previous)
            } catch {
                message += " The previous runtime did not start again: \(FailureDetail.describe(error))"
            }
        }
        await instance.endMaintenance(lease)
        return .processFailed(message)
    }
}
