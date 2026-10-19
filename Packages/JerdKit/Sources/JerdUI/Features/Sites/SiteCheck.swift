import JerdWeb

/// One connection check of a site and its honest result.
struct SiteCheck: Equatable {
    let title: String
    let result: String
    let passed: Bool

    /// The approval comes from the helper. A served site passed the private FPM ping and the
    /// system HTTPS check when it started, because the environment is ready only after both.
    @MainActor
    static func checks(for site: Site, in model: SitesModel) -> [SiteCheck] {
        let approved = model.isApproved(site)
        let served = model.environment.siteIDs.contains(site.id)
        let approval = site.aliases.isEmpty ? "Approved for this hostname" : "Approved for the hostname and aliases"
        return [
            SiteCheck(title: "HTTPS setup", result: approved ? approval : "Approval required", passed: approved),
            SiteCheck(
                title: "PHP-FPM", result: served ? "Passed at start" : "Checked when the site starts",
                passed: served),
            SiteCheck(
                title: "System HTTPS", result: served ? "Passed at start" : "Checked when the site starts",
                passed: served),
        ]
    }
}
