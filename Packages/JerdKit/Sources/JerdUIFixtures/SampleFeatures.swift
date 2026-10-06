import JerdDesign
import JerdUI

/// The Sites feature summary for each dashboard state, until the Sites feature lands. The
/// data services are real models on `InMemoryServicePorts`.
@MainActor
public enum SampleFeatures {
    /// Which state the sample features show.
    public enum Variant: Sendable {
        case empty, populated, busy, long
    }

    public static func all(_ variant: Variant) -> [InMemoryFeature] {
        [sites(variant)]
    }

    static func action(_ id: String, _ title: String, enabled: Bool = true, primary: Bool = false) -> FeatureAction {
        FeatureAction(id: id, title: title, isEnabled: enabled, isPrimary: primary) {}
    }

    static func sites(_ variant: Variant) -> InMemoryFeature {
        let summary: FeatureSummary
        switch variant {
        case .empty:
            summary = FeatureSummary(
                status: DisplayStatus("No sites", tone: .idle),
                summary: "Register an existing PHP project to serve it over HTTPS.",
                actions: [action("sites.add", "Add Site…", primary: true)])
        case .populated:
            summary = FeatureSummary(
                status: DisplayStatus("2 running", tone: .ready),
                summary: "3 registered · 2 enabled · 1/1 tunnels connected",
                actions: [action("sites.stop-all", "Stop All Sites")])
        case .busy:
            summary = FeatureSummary(
                status: DisplayStatus("Starting…", tone: .busy), summary: "3 registered · 2 enabled",
                actions: [action("sites.stop-all", "Stop All Sites")])
        case .long:
            summary = FeatureSummary(
                status: DisplayStatus("12 running", tone: .ready),
                summary: "24 registered · 18 enabled · 3/5 tunnels connected · northwind-storefront-staging.test",
                actions: [action("sites.stop-all", "Stop All Sites")])
        }
        let feature = InMemoryFeature(section: .sites, summary: summary, shutdownPhase: .webEnvironment)
        feature.menuItems = sitesMenu(variant)
        return feature
    }

    static func sitesMenu(_ variant: Variant) -> [MenuBarItem] {
        guard variant != .empty else { return [.text("Stopped", id: "sites.state")] }
        return [
            .text("Ready", id: "sites.state"),
            .action(action("sites.open.studio", "Open Studio")),
            .action(action("sites.stop-all", "Stop All Sites")),
        ]
    }
}
