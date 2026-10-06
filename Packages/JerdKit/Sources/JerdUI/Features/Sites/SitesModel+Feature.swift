import JerdDesign
import JerdWeb

extension SitesModel: WorkspaceFeature {
    public var section: AppSection { .sites }
    public var pollingPolicy: PollingPolicy { .environment }

    /// Tunnels, then PHP-FPM and Caddy last. The shared lock ends pending site work first.
    public var shutdownParticipants: [any ShutdownParticipant] { [tunnels, self] }

    /// The environment at 500 ms and the tunnels at 1 s while visible (spec F 2.9).
    public var pollingTasks: [PollingTask] {
        [
            PollingTask(policy: .environment) { [weak self] in await self?.refresh() },
            PollingTask(policy: .tunnels) { [weak self] in await self?.tunnels.refresh() },
        ]
    }

    /// File › New Site… (⌘N).
    public var newItemAction: FeatureAction? {
        FeatureAction(id: "sites.new", title: "New Site…", isEnabled: canChange) { [weak self] in
            self?.beginAdd()
        }
    }

    public var summary: FeatureSummary {
        FeatureSummary(status: cardStatus, summary: cardSummary, actions: cardActions)
    }

    /// Site work affects every site, so it shows on every page, with Stop when it can stop.
    public var bannerActivity: BannerActivity? {
        guard let message = operation.workingMessage else { return nil }
        guard case .working(_, true) = operation else { return BannerActivity(message: message) }
        return BannerActivity(message: message, stop: stopAllAction(id: "sites.banner.stop", title: "Stop All Sites"))
    }

    public var menuItems: [MenuBarItem] {
        var items: [MenuBarItem] = [
            .text(SiteStatusPolicy.overall(environment, isWorking: operation.isWorking).label, id: "sites.state")
        ]
        for site in configuration.sites where site.isEnabled {
            items.append(
                .action(
                    FeatureAction(
                        id: "sites.open.\(site.id.uuidString)", title: "Open \(site.displayName)",
                        isEnabled: environment.siteIDs.contains(site.id)
                    ) { [weak self] in self?.openInBrowser(site) }))
        }
        if let runAction = runAllAction(primary: false) { items.append(.action(runAction)) }
        items += tunnels.menuItems
        return items
    }

    private var cardStatus: DisplayStatus {
        if operation.isWorking { return DisplayStatus("Working…", tone: .busy) }
        if !environment.siteIDs.isEmpty { return DisplayStatus("\(environment.siteIDs.count) running", tone: .ready) }
        if configuration.sites.isEmpty { return DisplayStatus("No sites", tone: .idle) }
        return SiteStatusPolicy.environment(environment.state)
    }

    private var cardSummary: String {
        guard !configuration.sites.isEmpty else { return "Register an existing PHP project to serve it over HTTPS." }
        var text = "\(configuration.sites.count) registered · \(enabledSiteIDs.count) enabled"
        if !tunnels.registrations.isEmpty {
            text += " · \(tunnels.connectedCount)/\(tunnels.registrations.count) tunnels connected"
        }
        return text
    }

    private var cardActions: [FeatureAction] {
        guard !configuration.sites.isEmpty || operation.isWorking else {
            return [
                FeatureAction(id: "sites.add", title: "Add Site…", isEnabled: canChange, isPrimary: true) {
                    [weak self] in
                    self?.shell.show(.section(.sites))
                    self?.beginAdd()
                }
            ]
        }
        return runAllAction(primary: true).map { [$0] } ?? []
    }

    /// Stop All Sites while sites run or work runs, else Start All Sites.
    private func runAllAction(primary: Bool) -> FeatureAction? {
        if canStopAll { return stopAllAction(id: "sites.stop-all", title: "Stop All Sites") }
        guard !enabledSiteIDs.isEmpty else { return nil }
        return FeatureAction(
            id: "sites.start-all", title: "Start All Sites", isEnabled: canStart && hasStoppedEnabledSite,
            isPrimary: primary
        ) { [weak self] in self?.startAll() }
    }

    private func stopAllAction(id: String, title: String) -> FeatureAction {
        FeatureAction(id: id, title: title, isEnabled: canStopAll) { [weak self] in self?.stopAll() }
    }
}
