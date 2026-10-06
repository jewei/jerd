import JerdProcess

/// Gives a definition access to the owned steps of the start that is in progress (setup phases
/// and initializers), with its clearance.
struct StartStepRunner: SetupPhaseRunning, InitializerRunning {
    let instance: ManagedInstance
    let clearance: StartClearance

    func runSetupPhase(_ plan: LaunchPlan) async throws {
        try await instance.runSetupPhase(plan, clearance: clearance)
    }

    func runInitializer(_ plan: InitializerPlan) async throws -> CommandResult {
        try await instance.runInitializer(plan, clearance: clearance)
    }
}
