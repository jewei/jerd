import JerdDesign
import JerdUI

/// Feature summaries for each dashboard state, as the feature models will report them.
@MainActor
public enum SampleFeatures {
    /// Which state the sample features show.
    public enum Variant: Sendable {
        case empty, populated, busy, long
    }

    public static func all(_ variant: Variant) -> [InMemoryFeature] {
        [sites(variant), databases(variant), storage(variant), mail(variant)]
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

    static func databases(_ variant: Variant) -> InMemoryFeature {
        let summary: FeatureSummary
        switch variant {
        case .empty:
            summary = FeatureSummary(
                status: DisplayStatus("No services", tone: .idle), summary: "Add MySQL, PostgreSQL, or Redis services.",
                actions: [action("databases.add", "Add Database…")])
        case .populated:
            summary = FeatureSummary(
                status: DisplayStatus("2 of 3 running", tone: .ready),
                summary: "Studio development, Studio cache, Reporting")
        case .busy:
            summary = FeatureSummary(status: DisplayStatus("Failed", tone: .failed), summary: "Studio development, Studio cache")
        case .long:
            summary = FeatureSummary(
                status: DisplayStatus("9 of 14 running", tone: .ready),
                summary:
                    "Studio development, Studio cache, Reporting warehouse with a long name, Billing replica, Search index, Analytics")
        }
        return InMemoryFeature(section: .databases, summary: summary, shutdownPhase: .databases)
    }

    static func storage(_ variant: Variant) -> InMemoryFeature {
        let running = variant == .populated || variant == .long
        let status: DisplayStatus =
            switch variant {
            case .empty: DisplayStatus("Stopped", tone: .idle)
            case .busy: DisplayStatus("Starting…", tone: .busy)
            case .populated, .long: DisplayStatus("Ready", tone: .ready)
            }
        let summary = FeatureSummary(
            status: status, summary: variant == .empty ? "0 buckets · S3 port 9000" : "3 buckets · S3 port 9000",
            actions: [
                running ? action("storage.stop", "Stop Storage") : action("storage.start", "Start Storage"),
                action("storage.console", "Open Console", enabled: running),
            ])
        return InMemoryFeature(section: .storage, summary: summary, shutdownPhase: .storage)
    }

    static func mail(_ variant: Variant) -> InMemoryFeature {
        let running = variant == .populated || variant == .long
        let summary = FeatureSummary(
            status: running ? DisplayStatus("Ready", tone: .ready) : DisplayStatus("Stopped", tone: .idle),
            summary: "SMTP port 1025 · Web port 8025",
            actions: [
                running ? action("mail.stop", "Stop Mail") : action("mail.start", "Start Mail"),
                action("mail.inbox", "Open Inbox", enabled: running),
            ])
        return InMemoryFeature(section: .mail, summary: summary, shutdownPhase: .mail)
    }
}
