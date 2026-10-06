import JerdWeb

extension SitesModel {
    /// The next step of a site page. A pending recovery comes first, because no site can
    /// change until it is done.
    public func nextStep(for site: Site) -> SiteNextStep {
        if needsRecovery { return .recover }
        if environment.siteIDs.contains(site.id) { return .open }
        return .start(needsApproval: !isApproved(site))
    }

    /// "Start All Sites", with "…" when a site that starts still needs HTTPS approval.
    public var startAllTitle: String {
        let needsApproval = configuration.sites.contains { $0.isEnabled && !isApproved($0) }
        return needsApproval ? "Start All Sites…" : "Start All Sites"
    }

    /// Opens Advanced, where the user recovers an interrupted HTTPS setup.
    public func openAdvanced() {
        shell.show(.dashboard(.advanced))
    }
}
