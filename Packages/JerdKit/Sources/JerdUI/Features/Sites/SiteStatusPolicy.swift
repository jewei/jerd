import JerdDesign
import JerdWeb

/// The status words of the web environment and of each site. Pure rules, so the sidebar, the
/// detail page, the dashboard card, and the menu bar always agree.
public enum SiteStatusPolicy {
    /// The environment state as a status, for example "Ready" or "Setup required".
    public static func environment(_ state: EnvironmentState) -> DisplayStatus {
        switch state {
        case .running: DisplayStatus("Ready", tone: .ready)
        case .starting: DisplayStatus("Starting…", tone: .busy)
        case .stopped: DisplayStatus("Stopped", tone: .idle)
        case .setupRequired: DisplayStatus("Setup required", tone: .attention)
        case .failed: DisplayStatus("Failed", tone: .failed)
        }
    }

    /// The status of one site. The first rule that matches wins: a disabled site, a served
    /// site, a site that waits while others run, running site work, then the environment.
    public static func site(_ site: Site, environment: EnvironmentSnapshot, isWorking: Bool) -> DisplayStatus {
        if !site.isEnabled { return DisplayStatus("Disabled", tone: .idle) }
        if environment.siteIDs.contains(site.id) { return DisplayStatus("Ready", tone: .ready) }
        if !environment.siteIDs.isEmpty { return DisplayStatus("Not running", tone: .idle) }
        if isWorking { return DisplayStatus("Working…", tone: .busy) }
        if case .running = environment.state { return DisplayStatus("Not running", tone: .idle) }
        return Self.environment(environment.state)
    }

    /// The status of the whole environment while site work can run.
    public static func overall(_ environment: EnvironmentSnapshot, isWorking: Bool) -> DisplayStatus {
        isWorking ? DisplayStatus("Working…", tone: .busy) : Self.environment(environment.state)
    }
}
