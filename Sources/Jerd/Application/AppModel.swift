import AppKit
import Observation
import JerdCore

enum AppSection { case dashboard, sites, databases, storage, mail }

@MainActor @Observable
final class AppModel {
    var selectedSection = AppSection.dashboard
    let appearance = AppAppearance()
    let updates = RuntimeUpdatesModel()
    let appUpdates = AppUpdatesModel()
    var selectedDashboard = DashboardSection.dashboard
    let databases = DatabaseModel()
    let storage = StorageModel()
    let mail = MailModel()
    var configuration = AppConfiguration()
    var selectedSiteID: UUID?
    var errorMessage: String?
    private(set) var isBusy = false
    private(set) var isShuttingDown = false
    var isLoaded = false
    var environmentState: EnvironmentState = .stopped
    var runningSiteIDs: Set<UUID> = []
    private var preparedAfterEdit: HTTPSSetup?
    var systemStatus = SystemSetupStatus()
    var pendingSetup: HTTPSSetup?
    var runtimeMessage = "Preparing PHP and Caddy…"
    private var work: Task<Void, Never>?
    private var workGeneration = 0
    private var backgroundGeneration: Int?
    private var backgroundWaiters: [CheckedContinuation<Void, Never>] = []
    private var monitor: Task<Void, Never>?
    private let helper = HelperClient()
    @ObservationIgnored private lazy var environment = LocalEnvironment(
        directory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("environment"), system: helper)
    let registry = SiteRegistry(store: JSONConfigurationStore(directory: JSONConfigurationStore.applicationDirectory))

    var selectedSite: Site? { configuration.sites.first { $0.id == selectedSiteID } }

    func showDashboard(_ section: DashboardSection) {
        selectedDashboard = section
        selectedSection = .dashboard
    }

    func load() {
        guard !isLoaded else { return }
        if !databases.isLoaded { databases.load() }
        if !storage.isLoaded { storage.load() }
        if !mail.isLoaded { mail.load() }
        updates.load()
        perform {
            self.configuration = try await self.registry.load()
            self.isLoaded = true
            self.selectedSiteID = self.configuration.sites.first?.id
            if let resources = Bundle.main.resourceURL {
                do {
                    let bundle = BundledRuntimes()
                    if try await bundle.needsBootstrap(configuration: self.configuration,
                        directory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtimes")) {
                        let (php, caddy) = try await bundle.install(
                            from: resources.appendingPathComponent("DevelopmentRuntimes"),
                            into: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtimes"))
                        self.configuration = try await self.registry.addRuntime(php)
                        if self.configuration.caddy == nil {
                            self.configuration = try await self.registry.setCaddy(caddy)
                        }
                    }
                    self.runtimeMessage = "PHP, Caddy, Composer, and the Laravel installer are installed and managed by Jerd."
                } catch {
                    self.runtimeMessage = "Bundled runtime setup failed: \(error.localizedDescription)"
                }
            }
            self.startMonitoring()
            await self.updates.refreshInstalled()
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
        guard !isBusy, !isShuttingDown else { return }
        workGeneration += 1
        let generation = workGeneration
        isBusy = true
        errorMessage = nil
        work = Task {
            defer { finishWork(generation) }
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func finishWork(_ generation: Int) {
        if workGeneration == generation { isBusy = false }
    }

    func beginBackgroundWork() throws -> Int {
        guard !isBusy, !isShuttingDown else {
            throw JerdError.unavailable("Wait for the current operation to finish.")
        }
        workGeneration += 1
        isBusy = true
        errorMessage = nil
        backgroundGeneration = workGeneration
        return workGeneration
    }

    func endBackgroundWork(_ generation: Int) {
        guard backgroundGeneration == generation else { return }
        backgroundGeneration = nil
        let waiters = backgroundWaiters
        backgroundWaiters.removeAll()
        waiters.forEach { $0.resume() }
        finishWork(generation)
    }

    private func waitForBackgroundWork() async {
        guard backgroundGeneration != nil else { return }
        await withCheckedContinuation { backgroundWaiters.append($0) }
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
        perform { try await self.changeDefaultRuntime(id) }
    }

    private func changeDefaultRuntime(_ id: UUID) async throws {
        let previous = configuration.defaultRuntimeID
        let wasRunning = !runningSiteIDs.isEmpty
        configuration = try await registry.setDefaultRuntime(id)
        do { if wasRunning { try await startEnvironment() } }
        catch {
            let failure = error.localizedDescription
            if let previous {
                do {
                    configuration = try await registry.setDefaultRuntime(previous)
                    if wasRunning { try await startEnvironment() }
                } catch { throw JerdError.process("PHP activation failed: \(failure) Restore failed: \(error.localizedDescription)") }
            }
            throw JerdError.process("PHP activation failed. The previous selection was restored. \(failure)")
        }
    }

    func activateRuntime(_ runtime: ManagedRuntime, useAsDefault: Bool) async throws {
        guard !isShuttingDown else { throw JerdError.unavailable("Jerd is shutting down.") }
        if runtime.kind == .php || runtime.kind == .caddy {
            guard isLoaded else { throw JerdError.unavailable("Load valid site settings before changing PHP or Caddy.") }
        }
        switch runtime.kind {
        case .php:
            guard let fpm = runtime.secondaryExecutable else { throw JerdError.invalid("The PHP-FPM executable is missing.") }
            let inspected = try await DevelopmentRuntimeProvider().inspectPHP(cli: runtime.executable, fpm: fpm,
                workDirectory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtime-inspection"))
            configuration = try await registry.addRuntime(inspected)
            if useAsDefault, let installed = configuration.runtimes.first(where: { $0.cliPath == runtime.executable.path }) {
                try await changeDefaultRuntime(installed.id)
            }
        case .caddy:
            let previous = configuration.caddy, wasRunning = !runningSiteIDs.isEmpty
            let inspected = try await DevelopmentRuntimeProvider().inspectCaddy(binary: runtime.executable,
                workDirectory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtime-inspection"))
            configuration = try await registry.setCaddy(inspected)
            do { if wasRunning { try await startEnvironment() } }
            catch {
                let failure = error.localizedDescription
                if let previous {
                    do {
                        configuration = try await registry.setCaddy(previous)
                        if wasRunning { try await startEnvironment() }
                    } catch { throw JerdError.process("Caddy activation failed: \(failure) Restore failed: \(error.localizedDescription)") }
                }
                throw JerdError.process("Caddy activation failed. The previous selection was restored. \(failure)")
            }
        case .mysql, .postgresql, .redis:
            guard let engine = DatabaseEngine(rawValue: runtime.kind.rawValue) else { return }
            try await databases.registerUpdatedRuntime(DatabaseRuntime(id: runtime.directory.lastPathComponent,
                engine: engine, version: runtime.version, path: runtime.directory.path))
        case .mailpit:
            try await mail.updateRuntime(MailRuntime(id: runtime.directory.lastPathComponent, version: runtime.version, path: runtime.directory.path))
        case .rustfs:
            try await storage.updateRuntime(StorageRuntime(id: runtime.directory.lastPathComponent, version: runtime.version, path: runtime.directory.path))
        case .composer, .laravel: try await updates.installer.activateCompanion(runtime)
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
    func stop() {
        guard !isShuttingDown else { return }
        let previous = work
        workGeneration += 1
        let generation = workGeneration
        isBusy = true
        errorMessage = nil
        work = Task {
            defer { finishWork(generation) }
            await previous?.value
            await waitForBackgroundWork()
            await stopEnvironment()
        }
    }

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
        isShuttingDown = true
        await updates.finishBeforeQuit()
        guard await storage.shutdown() else {
            isShuttingDown = false
            updates.resumeAfterCancelledQuit()
            selectedSection = .storage
            errorMessage = "Storage could not stop safely. Jerd will remain open. Retry Stop in Storage."
            return false
        }
        guard await mail.shutdown() else {
            isShuttingDown = false
            updates.resumeAfterCancelledQuit()
            storage.resumeAfterCancelledQuit()
            selectedSection = .mail
            errorMessage = "The mail service could not stop safely. Jerd will remain open. Retry Stop in Mail."
            return false
        }
        guard await databases.shutdown() else {
            isShuttingDown = false
            updates.resumeAfterCancelledQuit()
            storage.resumeAfterCancelledQuit()
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
