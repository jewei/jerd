import JerdProcess

/// Gives a definition access to setup phases of the start that is in progress, with its clearance.
struct SetupPhaseRunner: SetupPhaseRunning {
    let instance: ManagedInstance
    let clearance: StartClearance

    func runSetupPhase(_ plan: LaunchPlan) async throws {
        try await instance.runSetupPhase(plan, clearance: clearance)
    }
}
