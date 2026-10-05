/// The service-specific steps of a runtime update. The transaction runs them in order while it
/// holds the instance lock.
public struct RuntimeUpdateSteps: Sendable {
    /// A step without a result.
    public typealias Step = @Sendable () async throws -> Void
    /// Reloads the restored settings and returns the definition that they describe.
    public typealias Reload = @Sendable () async throws -> any ServiceDefinition

    /// Validates the current data against the previous runtime, before any backup. It must not
    /// create data.
    public var validatePrevious: Step
    /// Saves the new runtime in the settings and rewrites identity and initialization markers.
    public var apply: Step
    /// Extra checks after the new server is ready, for example that every bucket is listed.
    public var verifyStarted: Step
    /// Reloads settings after a restore.
    public var reloadAfterRestore: Reload

    public init(
        validatePrevious: @escaping Step, apply: @escaping Step, verifyStarted: @escaping Step = {},
        reloadAfterRestore: @escaping Reload
    ) {
        self.validatePrevious = validatePrevious
        self.apply = apply
        self.verifyStarted = verifyStarted
        self.reloadAfterRestore = reloadAfterRestore
    }
}
