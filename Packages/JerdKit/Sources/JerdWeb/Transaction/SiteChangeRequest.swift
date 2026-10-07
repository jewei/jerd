import Foundation

/// Which sites a change runs afterwards.
public enum RunSelection: Equatable, Sendable {
    /// Keep the running subset. New or newly enabled sites join a run. With nothing running, only
    /// `startIfStopped` (a new site save) starts the enabled new sites.
    case keepRunning(startIfStopped: Bool)
    /// Run exactly these enabled sites (Start or Stop of sites). An empty set stops the run.
    case exactly(Set<UUID>)
}

/// The input of one transaction run: the saved and the candidate configuration and the selection.
struct SiteChangeRequest: Sendable {
    let previous: AppConfiguration
    let candidate: AppConfiguration
    let selection: RunSelection

    /// Hostnames that the edit removes or renames. They leave the approved set.
    var removedHostnames: Set<String> {
        Set(previous.sites.map(\.hostname)).subtracting(candidate.sites.map(\.hostname))
    }

    /// Every registered hostname, enabled or not, so an approval keeps disabled sites approved.
    var registeredHostnames: [String] { candidate.sites.map(\.hostname) }
}
