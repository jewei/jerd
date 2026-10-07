/// Runs a setup phase of a first start: a temporary server that must become ready, own exactly
/// its planned listeners, and then stop gracefully while the instance lock stays held.
public protocol SetupPhaseRunning: Sendable {
    func runSetupPhase(_ plan: LaunchPlan) async throws
}
