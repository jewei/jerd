import Darwin
import JerdFoundation
import JerdProcess

/// A server process that Jerd started and owns, with the plan that started it.
///
/// It joins the supervisor, the server log, and the run record: a launch rotates the log and
/// spawns the process, and only an owned process gets a record.
public struct OwnedServiceProcess: Sendable {
    public let token: ProcessToken
    public let processID: pid_t
    public let plan: LaunchPlan
    private let processes: any ProcessControlling

    /// Rotates the log and starts `plan`. Returns only a process that the supervisor owns.
    ///
    /// When the spawn fails or produces no owned child, the launch ends (`LaunchPlan.didStop`
    /// runs) and the error names the end of the log.
    public static func launch(
        _ plan: LaunchPlan, log: ServiceLog, processes: any ProcessControlling, policy: StopPolicy,
        messages: ServiceMessages
    ) async throws -> OwnedServiceProcess {
        let token: ProcessToken
        do {
            try log.rotate()
            token = try await processes.start(plan.request, log: log.file)
        } catch {
            plan.end()
            throw error
        }
        guard let pid = await processes.processID(of: token) else {
            _ = await processes.stop(token, policy: policy)
            plan.end()
            let tail = log.tail(redacting: plan.secrets, fallback: messages.logUnavailable)
            throw JerdError.processFailed("\(messages.couldNotStart) \(tail)")
        }
        return OwnedServiceProcess(token: token, processID: pid, plan: plan, processes: processes)
    }

    /// True while the leader has not exited.
    public func isAlive() async -> Bool {
        await processes.state(of: token) == .running
    }

    /// Stops the process group with `policy`. Concurrent stops share one outcome.
    public func stop(policy: StopPolicy) async -> StopOutcome {
        await processes.stop(token, policy: policy)
    }

    /// Saves the run record of this process at the cleared location.
    /// - Throws: when the identity cannot be captured. A fallback record is then saved.
    public func saveRecord(
        runtimeID: String, signal: Int32, clearance: StartClearance, recorder: ActiveRunRecorder
    )
        throws
    {
        try recorder.record(processID: processID, runtimeID: runtimeID, gracefulSignal: signal, clearance: clearance)
    }
}
