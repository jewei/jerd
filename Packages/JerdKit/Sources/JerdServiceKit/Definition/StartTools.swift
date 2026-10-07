import JerdFoundation
import JerdProcess

/// The effects that a definition can use while it prepares a start.
public struct StartTools: Sendable {
    /// Runs one-shot commands, for example a version probe or a client probe.
    public let commands: any CommandRunning
    private let setup: any SetupPhaseRunning
    private let initializer: (any InitializerRunning)?

    /// - Parameter initializer: runs initializers as owned processes. Without it,
    ///   `runInitializer` refuses, so an initializer never runs outside the instance.
    public init(
        commands: any CommandRunning, setup: any SetupPhaseRunning, initializer: (any InitializerRunning)? = nil
    ) {
        self.commands = commands
        self.setup = setup
        self.initializer = initializer
    }

    /// Runs `plan` to readiness, verifies its listeners, and stops it. The lock stays held.
    /// - Throws: the readiness or listener error. A stop timeout keeps the process owned.
    public func runSetupPhase(_ plan: LaunchPlan) async throws {
        try await setup.runSetupPhase(plan)
    }

    /// Runs `plan` as an owned process with a run record, and waits for its exit. The lock stays held.
    /// - Returns: the exit status and the redacted end of the output.
    /// - Throws: `.timedOut` after a timeout. A stop timeout keeps the process owned, and the
    ///   start then ends `stuck`.
    public func runInitializer(_ plan: InitializerPlan) async throws -> CommandResult {
        guard let initializer else { throw JerdError.unavailable(ServiceMessages.initializerUnavailable) }
        return try await initializer.runInitializer(plan)
    }
}
