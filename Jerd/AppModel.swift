import AppKit
import Observation
import JerdCore

enum AppSection { case sites, databases, mail }

@MainActor @Observable
final class AppModel {
    var selectedSection = AppSection.sites
    let databases = DatabaseModel()
    let mail = MailModel()
    var configuration = AppConfiguration()
    var selectedSiteID: UUID?
    var errorMessage: String?
    var isBusy = false
    var isLoaded = false
    var environmentState: EnvironmentState = .stopped
    var runningSiteIDs: Set<UUID> = []
    private var preparedAfterEdit: HTTPSSetup?
    var systemStatus = SystemSetupStatus()
    var pendingSetup: HTTPSSetup?
    var runtimeMessage = "Preparing PHP and Caddy…"
    private var work: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private let helper = HelperClient()
    @ObservationIgnored private lazy var environment = LocalEnvironment(
        directory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("environment"), system: helper)
    let registry = SiteRegistry(store: JSONConfigurationStore(directory: JSONConfigurationStore.applicationDirectory))

    var selectedSite: Site? { configuration.sites.first { $0.id == selectedSiteID } }

    func load() {
        guard !isLoaded else { return }
        perform {
            self.configuration = try await self.registry.load()
            self.isLoaded = true
            self.selectedSiteID = self.configuration.sites.first?.id
            if let resources = Bundle.main.resourceURL {
                do {
                    let (php, caddy) = try await BundledRuntimes().install(
                        from: resources.appendingPathComponent("DevelopmentRuntimes"),
                        into: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtimes"))
                    self.configuration = try await self.registry.addRuntime(php)
                    if self.configuration.caddy == nil {
                        self.configuration = try await self.registry.setCaddy(caddy)
                    }
                    self.runtimeMessage = "PHP, Caddy, Composer, and the Laravel installer are installed and managed by Jerd."
                } catch {
                    self.runtimeMessage = "Bundled runtime setup failed: \(error.localizedDescription)"
                }
            }
            self.startMonitoring()
            self.databases.load()
            self.mail.load()
            if await self.helper.isEnabled() { self.systemStatus = try await self.helper.status() }
        }
    }

    private func startMonitoring() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self else { return }
                let snapshot = await self.environment.snapshot()
                guard !self.isBusy else { continue }
                self.environmentState = snapshot.state
                self.runningSiteIDs = snapshot.state == .running ? snapshot.siteIDs : []
            }
        }
    }

    func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        work = Task {
            defer { isBusy = false }
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func save(_ site: Site, confirmed: Bool, completion: @escaping () -> Void) {
        perform {
            let wasRunning = !self.runningSiteIDs.isEmpty
            let isNew = !self.configuration.sites.contains(where: { $0.id == site.id })
            if self.runningSiteIDs.contains(site.id) { await self.stopEnvironment() }
            self.configuration = try await self.registry.saveSite(site, documentRootConfirmed: confirmed)
            self.selectedSiteID = site.id
            if (wasRunning || isNew), !self.enabledSites.isEmpty {
                if self.enabledSites.allSatisfy(self.hasSetup) { try await self.startEnvironment() }
                else { self.preparedAfterEdit = try await self.prepareSetup() }
            }
            completion()
        }
    }

    func presentPreparedSetup() {
        if let preparedAfterEdit { pendingSetup = preparedAfterEdit; self.preparedAfterEdit = nil }
    }

    func remove(_ site: Site) {
        perform {
            let wasRunning = !self.runningSiteIDs.isEmpty
            if self.runningSiteIDs.contains(site.id) || self.systemStatus.hostnames.contains(site.hostname) {
                await self.stopEnvironment()
            }
            if self.systemStatus.hostnames.contains(site.hostname) {
                try await self.environment.removeHostname(site.hostname)
                self.systemStatus = try await self.helper.status()
            }
            self.configuration = try await self.registry.removeSite(site.id)
            self.selectedSiteID = self.configuration.sites.first?.id
            if wasRunning, !self.enabledSites.isEmpty { try await self.startEnvironment() }
        }
    }

    func toggleEnabled(_ site: Site) {
        perform {
            let wasRunning = !self.runningSiteIDs.isEmpty
            if self.runningSiteIDs.contains(site.id) { await self.stopEnvironment() }
            self.configuration = try await self.registry.setEnabled(site.id, enabled: !site.isEnabled)
            if wasRunning, !self.enabledSites.isEmpty { try await self.startEnvironment() }
        }
    }

    func setDefaultRuntime(_ id: UUID) {
        perform {
            let wasRunning = !self.runningSiteIDs.isEmpty
            self.configuration = try await self.registry.setDefaultRuntime(id)
            if wasRunning { try await self.startEnvironment() }
        }
    }

    func importPHP(cli: URL, fpm: URL) {
        perform {
            let runtime = try await DevelopmentRuntimeProvider().inspectPHP(cli: cli, fpm: fpm,
                workDirectory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtime-inspection"))
            self.configuration = try await self.registry.addRuntime(runtime)
        }
    }

    func importCaddy(_ binary: URL) {
        perform {
            let runtime = try await DevelopmentRuntimeProvider().inspectCaddy(binary: binary,
                workDirectory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtime-inspection"))
            self.configuration = try await self.registry.setCaddy(runtime)
        }
    }

    var stateLabel: String {
        switch environmentState {
        case .running: "Ready"
        case .starting: "Starting…"
        case .stopped: "Stopped"
        case .setupRequired: "Setup required"
        case .failed: "Failed"
        }
    }

    func hasSetup(_ site: Site) -> Bool {
        systemStatus.hostnames.contains(site.hostname) && systemStatus.hostsConfigured && systemStatus.trustConfigured && systemStatus.trustPolicy == .serverTLS
    }

    private var enabledSites: [Site] {
        configuration.sites.filter(\.isEnabled).sorted { $0.hostname < $1.hostname }
    }

    private func prepareSetup() async throws -> HTTPSSetup {
        for site in enabledSites { _ = try configuration.runtime(for: site) }
        guard let caddy = configuration.caddy else { throw JerdError.unavailable("Caddy is unavailable. Check PHP and Caddy settings.") }
        return try await environment.prepare(sites: enabledSites, caddy: caddy)
    }

    func prepareHTTPS() {
        perform { self.pendingSetup = try await self.prepareSetup() }
    }

    func approveHTTPS(_ setup: HTTPSSetup) {
        perform {
            guard Set(setup.request.hostnames) == Set(self.enabledSites.map(\.hostname)) else {
                throw JerdError.invalid("The enabled sites changed. Review HTTPS setup again.")
            }
            try await self.helper.registerAfterApproval()
            try await self.environment.apply(setup)
            self.runningSiteIDs.removeAll()
            self.systemStatus = try await self.helper.status()
            self.pendingSetup = nil
            try await self.startEnvironment()
        }
    }

    func start() { perform { try await self.startEnvironment() } }
    func stop() { perform { await self.stopEnvironment() } }

    func removeSystemSetup() {
        perform {
            await self.stopEnvironment()
            try await self.environment.removeSetup()
            self.systemStatus = SystemSetupStatus()
            try await self.helper.unregisterAfterCleanup()
        }
    }

    private func startEnvironment() async throws {
        let sites = enabledSites
        guard !sites.isEmpty else { throw JerdError.invalid("Enable at least one registered site.") }
        let selections = try sites.map { SiteRuntime(site: $0, runtime: try configuration.runtime(for: $0)) }
        guard let caddy = configuration.caddy else { throw JerdError.unavailable("Caddy is unavailable.") }
        if !sites.allSatisfy(hasSetup) {
            pendingSetup = try await prepareSetup()
            return
        }
        await stopEnvironment()
        environmentState = .starting
        do {
            try await environment.start(sites: selections, caddy: caddy)
            environmentState = await environment.state
            runningSiteIDs = Set(sites.map(\.id))
        } catch {
            environmentState = await environment.state
            throw error
        }
    }

    private func stopEnvironment() async {
        await environment.stop()
        runningSiteIDs.removeAll()
        environmentState = await environment.state
    }

    func open(_ site: Site) {
        guard runningSiteIDs.contains(site.id), environmentState == .running,
              let url = URL(string: "https://\(site.hostname)") else { return }
        NSWorkspace.shared.open(url)
    }

    func shutdown() async -> Bool {
        guard await mail.shutdown() else {
            selectedSection = .mail
            errorMessage = "The mail service could not stop safely. Jerd will remain open. Retry Stop in Mail."
            return false
        }
        guard await databases.shutdown() else {
            mail.resumeAfterCancelledQuit()
            errorMessage = "A database service could not stop safely. Jerd will remain open. Check Databases and retry Stop."
            return false
        }
        await work?.value
        monitor?.cancel()
        await stopEnvironment()
        await helper.invalidate()
        return true
    }

    static func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseExecutable(message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Select executable"
        return panel.runModal() == .OK ? panel.url : nil
    }
}
