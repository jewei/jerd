import JerdDatabases

/// The result of the last runtime installation that the Databases page started: why it failed,
/// or that the user cancelled it. A success needs no notice: the engine shows as installed.
public struct DatabaseRuntimeNotice: Equatable, Sendable {
    public let engine: DatabaseEngine
    public let message: String
    public let isFailure: Bool

    public init(engine: DatabaseEngine, message: String, isFailure: Bool) {
        self.engine = engine
        self.message = message
        self.isFailure = isFailure
    }
}
