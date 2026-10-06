import JerdProcess

/// Runs an initializer of a first start (see `InitializerPlan`) as an owned process of the
/// instance, while the instance lock stays held.
public protocol InitializerRunning: Sendable {
    /// - Returns: the exit status and the redacted end of the output.
    /// - Throws: a timeout (`.timedOut`), a launch error, or a stop error. A stop timeout keeps
    ///   the process owned.
    func runInitializer(_ plan: InitializerPlan) async throws -> CommandResult
}
