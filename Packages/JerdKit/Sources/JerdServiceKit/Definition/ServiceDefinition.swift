/// What one kind of managed service adds to the shared lifecycle: its fixed facts, its version
/// probe, its data preparation, and the plan of its server process.
///
/// `ManagedInstance` runs the shared safety steps in a fixed order and calls the definition in between:
/// free ports → instance folder → lock → previous run record → `versionProbe` → `prepareStart` →
/// launch → readiness → listener ownership → `completeStart` → running.
public protocol ServiceDefinition: Sendable {
    /// The fixed facts: names, folders, ports, the stop signal, and the messages.
    var profile: ServiceProfile { get }

    /// The check that the runtime binary reports the registered version. It runs before any data
    /// file is created or opened.
    var versionProbe: VersionProbe { get }

    /// Checks the data identity, prepares credentials and first-time initialization, writes the
    /// configuration of this launch, and returns the plan of the server process.
    ///
    /// It runs with the instance lock held and a cleared run record. A failure leaves every
    /// existing data file in place.
    func prepareStart(_ tools: StartTools) async throws -> LaunchPlan

    /// Saves markers that prove a successful start, for example `initialized.json`. It runs after
    /// the readiness and listener checks and before the state becomes `running`.
    func completeStart() async throws
}

extension ServiceDefinition {
    /// Most services have nothing to save after a start.
    public func completeStart() async throws {}
}
