import JerdDesign
import JerdWeb

extension SitesModel: WorkspaceFeature {
    public var section: AppSection { .sites }
    public var pollingPolicy: PollingPolicy { .environment }

    /// Tunnels, then PHP-FPM and Caddy last. The shared lock ends pending site work first.
    public var shutdownParticipants: [any ShutdownParticipant] { [tunnels, self] }

    /// The environment at 500 ms and the tunnels at 1 s while visible.
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
            // The line names its subject, like the Storage and Mail submenus, and says what
            // the card says.
            .text("Sites: \(cardStatus.label)", id: "sites.state")
        ]
        for site in configuration.sites where site.isEnabled {
            items.append(
                .action(
                    FeatureAction(
                        id: "sites.open.\(site.id.uuidString)", title: "Open \(site.displayName)",
                        isEnabled: environment.siteIDs.contains(site.id) && !isBusy
                    ) { [weak self] in self?.openInBrowser(site) }))
        }
        if let runAction = runAllAction { items.append(.action(runAction)) }
        items += tunnels.menuItems
        return items
    }

    private var cardStatus: DisplayStatus {
        if !isLoaded {
            return operation.failureMessage == nil
                ? ServiceCardNotice.preparingStatus : DisplayStatus("Not loaded", tone: .failed)
        }
        if operation.isWorking { return DisplayStatus("Working…", tone: .busy) }
        if !environment.siteIDs.isEmpty { return DisplayStatus("\(environment.siteIDs.count) running", tone: .ready) }
        if configuration.sites.isEmpty { return DisplayStatus("No sites", tone: .idle) }
        return SiteStatusPolicy.environment(environment.state)
    }

    private var cardSummary: String {
        if !isLoaded {
            return operation.failureMessage == nil ? "Preparing your sites…" : "Site settings could not be loaded."
        }
        guard !configuration.sites.isEmpty else { return "Register an existing PHP project to serve it over HTTPS." }
        var text = "\(configuration.sites.count) registered · \(enabledSiteIDs.count) enabled"
        if !tunnels.registrations.isEmpty {
            text += " · \(tunnels.connectedCount)/\(tunnels.registrations.count) tunnels connected"
        }
        return text
    }

    /// Add Site… without sites; else Start All, or Stop All and Open Site while sites run
    /// (`CardActionRule`).
    private var cardActions: [FeatureAction] {
        // Without sites there is nothing to stop, also while other site work runs.
        guard !configuration.sites.isEmpty else {
            let add = FeatureAction(
                id: "sites.add", title: "Add Site…", isEnabled: canChange, unavailableReason: addSiteUnavailableReason
            ) { [weak self] in
                self?.shell.show(.section(.sites))
                self?.beginAdd()
            }
            return CardActionRule.actions(.add(add))
        }
        guard let run = runAllAction else { return [] }
        guard showsStopAll else {
            // "Start All Sites…" asks for HTTPS approval first; the short title keeps the ellipsis.
            return CardActionRule.actions(.start(run.titled(run.title.hasSuffix("…") ? "Start All…" : "Start All")))
        }
        return CardActionRule.actions(.stop(run.titled("Stop All")), open: openSiteAction)
    }

    /// Why Add Site… is off.
    private var addSiteUnavailableReason: String {
        if !isLoaded {
            return operation.failureMessage == nil
                ? "Jerd is preparing your sites." : "Site settings could not be loaded."
        }
        if needsRecovery { return "Recover the interrupted HTTPS setup in Advanced first." }
        return "Wait for the current work to end."
    }

    /// Opens the first served site in sidebar order in the browser. The help and the spoken
    /// title name the site; the menu bar menu lists every served site.
    private var openSiteAction: FeatureAction? {
        guard let site = configuration.sites.first(where: { environment.siteIDs.contains($0.id) }) else { return nil }
        return FeatureAction(
            id: "sites.card.open", title: "Open Site", spokenTitle: "Open \(site.displayName)", isEnabled: !isBusy
        ) { [weak self] in self?.openInBrowser(site) }
    }

    /// Stop All Sites while sites run or work runs, else Start All Sites.
    private var runAllAction: FeatureAction? {
        if showsStopAll { return stopAllAction(id: "sites.stop-all", title: "Stop All Sites") }
        guard !enabledSiteIDs.isEmpty else { return nil }
        return FeatureAction(
            id: "sites.start-all", title: startAllTitle, isEnabled: canChange && hasStoppedEnabledSite
        ) { [weak self] in self?.startAll() }
    }

    private func stopAllAction(id: String, title: String) -> FeatureAction {
        FeatureAction(id: id, title: title, isEnabled: canStopAll) { [weak self] in self?.stopAll() }
    }
}
