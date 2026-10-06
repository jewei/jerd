import Foundation
import JerdFoundation
import JerdUI
import JerdWeb

/// The Sites port on the web domain. Every edit, Start, and Stop goes through the one site change
/// transaction. A change that needs HTTPS approval waits here under the ID of its approval sheet,
/// until the user approves or discards it.
package actor LiveSitesPort: SitesPort {
    let setup: DevelopmentRuntimeSetup
    let sites: any SiteChangeApplying
    let coordinator: any EnvironmentControlling
    let gateway: any HTTPSSetupControlling
    let helper: any HelperControlling
    let detector: ProjectDetector
    let environmentLayout: EnvironmentLayout
    let loginItems: any LoginItemsOpening
    /// Changes that wait for approval, by `HTTPSApproval.id`: the call that continues each one.
    private var pending: [UUID: @Sendable () async throws -> AppConfiguration] = [:]

    package init(
        setup: DevelopmentRuntimeSetup, sites: any SiteChangeApplying, coordinator: any EnvironmentControlling,
        gateway: any HTTPSSetupControlling, helper: any HelperControlling, environmentLayout: EnvironmentLayout,
        detector: ProjectDetector = ProjectDetector(), loginItems: any LoginItemsOpening = SystemSettingsLoginItems()
    ) {
        self.setup = setup
        self.sites = sites
        self.coordinator = coordinator
        self.gateway = gateway
        self.helper = helper
        self.environmentLayout = environmentLayout
        self.detector = detector
        self.loginItems = loginItems
    }

    package init(domain: LiveDomain) {
        self.init(
            setup: domain.developmentRuntimes, sites: domain.web.transaction, coordinator: domain.web.coordinator,
            gateway: domain.web.gateway, helper: domain.helper, environmentLayout: domain.layout.environment)
    }

    package func loadConfiguration() async throws -> AppConfiguration {
        try await setup.loadConfiguration()
    }

    package func environment() async -> EnvironmentSnapshot {
        await coordinator.snapshot()
    }

    package func setupStatus() async throws -> HTTPSSetupStatus {
        try await gateway.status()
    }

    package func localAuthority() async throws -> InstallationAuthority? {
        try InstallationAuthority.read(environmentLayout)
    }

    package func apply(_ change: SiteChange, startIfStopped: Bool) async throws -> SiteChangeOutcome {
        await outcome(of: try await sites.apply(change, startIfStopped: startIfStopped))
    }

    package func run(_ siteIDs: Set<UUID>) async throws -> SiteChangeOutcome {
        await outcome(of: try await sites.run(siteIDs))
    }

    /// Registers the helper first, because the transaction's setup step talks to it. A failure
    /// keeps the waiting change, so the user can retry from the same sheet.
    package func approve(_ approval: HTTPSApproval) async throws -> AppConfiguration {
        guard let resume = pending[approval.id] else {
            throw JerdError.unavailable("This HTTPS approval is no longer valid. Make the site change again.")
        }
        try await helper.approve()
        let configuration = try await resume()
        pending[approval.id] = nil
        return configuration
    }

    package func discard(_ approval: HTTPSApproval) async {
        pending[approval.id] = nil
    }

    package func requestStop() async {
        await sites.requestStop()
    }

    /// Stops PHP-FPM and Caddy for Quit and closes the helper connection; the helper ends the
    /// port lease when the connection closes.
    package func stopEnvironment() async throws {
        await coordinator.stop()
        await helper.invalidate()
    }

    package func suggestDocumentRoot(projectPath: String) async throws -> DocumentRootSuggestion {
        try detector.suggestDocumentRoot(projectPath: projectPath)
    }

    package func environmentLogs() async -> URL? {
        let folder = environmentLayout.logsDirectory
        return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
    }

    private func outcome(of step: SiteChangeStep) async -> SiteChangeOutcome {
        switch step {
        case .committed(let configuration):
            return .committed(configuration)
        case .needsApproval(let setup, let resume):
            let id = UUID()
            pending[id] = resume
            return .needsApproval(
                SiteChangeMapping.approval(id: id, setup: setup, approvedHostnames: await approvedHostnames()))
        }
    }

    /// True while a change waits under this approval.
    package func isWaiting(_ approval: HTTPSApproval) -> Bool {
        pending[approval.id] != nil
    }

    /// The approved hostnames, for the "Setup Removed For" list. An unreadable status shows no
    /// removals; the approval itself reads the status again and fails safely.
    private func approvedHostnames() async -> [String] {
        do {
            return try await gateway.status().hostnames
        } catch {
            return []
        }
    }
}
