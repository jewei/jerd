import Foundation

/// The state of the environment and the sites that it serves, for the app.
public struct EnvironmentSnapshot: Equatable, Sendable {
    public let state: EnvironmentState
    /// The served sites. Empty unless the state is `running`.
    public let siteIDs: Set<UUID>

    public init(state: EnvironmentState, siteIDs: Set<UUID>) {
        self.state = state
        self.siteIDs = state == .running ? siteIDs : []
    }
}
