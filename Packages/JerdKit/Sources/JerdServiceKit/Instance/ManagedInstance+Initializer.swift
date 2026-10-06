import JerdFoundation
import JerdProcess

extension ManagedInstance {
    /// Runs one initializer (see `InitializerPlan`) inside the current start.
    ///
    /// The process gets a run record, and the lock stays held. After its exit or its timeout,
    /// its group is stopped gracefully, which also reaps it. A stop timeout keeps the process
    /// owned, so the start ends `stuck` with the lock and the record, and Quit is cancelled.
    func runInitializer(_ plan: InitializerPlan, clearance: StartClearance) async throws -> CommandResult {
        guard state == .starting else { throw JerdError.unavailable(messages.busy) }
        let launchPlan = plan.launchPlan
        let (owned, exit) = try await removingSecretFiles(of: launchPlan) {
            let owned = try await launch(launchPlan, clearance: clearance)
            return (owned, await effects.processes.waitForExit(of: owned.token, timeout: plan.timeout))
        }
        let stop = await stopOwned(owned, keepLock: true, intent: .startStep)
        let output = definition.profile.log.tail(redacting: plan.secrets, fallback: "")
        if let message = stop.failureMessage {
            let detail = exit.isRunning ? "\(plan.timeoutMessage) \(message)" : message
            // A process that is still owned must not be stopped a second time by the start
            // failure path.
            throw process == nil ? JerdError.processFailed(detail) : RetainedProcessError(message: detail)
        }
        if exit.isRunning {
            throw JerdError.timedOut(output.isEmpty ? plan.timeoutMessage : "\(plan.timeoutMessage) \(output)")
        }
        guard let status = exit.exitCode else {
            throw JerdError.processFailed(ServiceMessages.initializerResultUnknown)
        }
        return CommandResult(status: status, output: output)
    }
}
