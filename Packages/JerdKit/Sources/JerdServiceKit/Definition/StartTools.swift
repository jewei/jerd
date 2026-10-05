import JerdProcess

/// The effects that a definition can use while it prepares a start.
public struct StartTools: Sendable {
    /// Runs one-shot commands, for example a version probe or a client probe.
    public let commands: any CommandRunning
    private let setup: any SetupPhaseRunning

    public init(commands: any CommandRunning, setup: any SetupPhaseRunning) {
        self.commands = commands
        self.setup = setup
    }

    /// Runs `plan` to readiness, verifies its listeners, and stops it. The lock stays held.
    /// - Throws: the readiness or listener error. A stop timeout keeps the process owned.
    public func runSetupPhase(_ plan: LaunchPlan) async throws {
        try await setup.runSetupPhase(plan)
    }
}
