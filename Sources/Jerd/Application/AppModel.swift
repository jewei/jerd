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
    private var preparedSiteChange: PreparedSiteChange?
    private var preparedSelection: UUID?
    private var canCancelWork = true
    private(set) var stopInProgress = false
    private(set) var operationMessage: String?
    var processFindings: [ProcessRecoveryFinding] = []
    var retainedBackups: [RetainedBackup] = []
    @ObservationIgnored private let processRecovery = ProcessRecoveryStore(directory: JSONConfigurationStore.applicationDirectory)
    @ObservationIgnored private let backupRetention = BackupRetentionStore(directory: JSONConfigurationStore.applicationDirectory)
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

    @ObservationIgnored private lazy var siteChanges = SiteConfigurationOperation(registry: registry, environment: environment)

    var canStop: Bool { !isShuttingDown && !stopInProgress }
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
                self.applyEnvironment(snapshot.state, siteIDs: snapshot.siteIDs)
            }
        }
    }

    func perform(cancellable: Bool = true, message: String = "Checking settings…", _ action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy, !isShuttingDown else { return }
        workGeneration += 1
        let generation = workGeneration
        isBusy = true
        canCancelWork = cancellable
        operationMessage = message
        errorMessage = nil
        work = Task {
            defer { finishWork(generation) }
            do { try await action() }
            catch is CancellationError { }
            catch { errorMessage = error.localizedDescription }
            if isLoaded, let latest = try? await registry.snapshot() { configuration = latest }
            await refreshEnvironment()
        }
    }

    private func finishWork(_ generation: Int) {
        if workGeneration == generation { isBusy = false; operationMessage = nil }
    }

    func beginBackgroundWork() throws -> Int {
        guard !isBusy, !isShuttingDown else {
            throw JerdError.unavailable("Wait for the current operation to finish.")
        }
        workGeneration += 1
        isBusy = true
        errorMessage = nil
        canCancelWork = true
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
            let isNew = !self.configuration.sites.contains(where: { $0.id == site.id })
            let result = try await self.siteChanges.apply(.save(site, confirmed: confirmed), startIfStopped: isNew)
            self.accept(result, selection: site.id, afterEditor: true)
            completion()
        }
    }

    private func accept(_ result: SiteChangeResult, selection: UUID? = nil, afterEditor: Bool = false) {
        switch result {
        case .committed(let configuration):
            self.configuration = configuration
            if let selection { selectedSiteID = selection }
            if !configuration.sites.contains(where: { $0.id == selectedSiteID }) { selectedSiteID = configuration.sites.first?.id }
        case .needsApproval(let change):
            preparedSiteChange = change
            preparedSelection = selection
            if afterEditor { preparedAfterEdit = change.setup }
            else { pendingSetup = change.setup; selectedSection = .sites }
        }
    }

    func presentPreparedSetup() {
        if let preparedAfterEdit { pendingSetup = preparedAfterEdit; self.preparedAfterEdit = nil }
    }

    func discardPreparedSetup() {
        guard !isBusy else { return }
        preparedSiteChange = nil; preparedSelection = nil; preparedAfterEdit = nil
    }

    func remove(_ site: Site) {
        perform(cancellable: false, message: "Removing the site registration. Complete or cancel any macOS approval prompt…") {
            self.accept(try await self.siteChanges.apply(.remove(site.id)))
            self.systemStatus = try await self.helper.status()
        }
    }

    func toggleEnabled(_ site: Site) {
        perform { self.accept(try await self.siteChanges.apply(.enabled(site.id, !site.isEnabled))) }
    }

    func setDefaultRuntime(_ id: UUID) {
        perform { try await self.changeDefaultRuntime(id) }
    }

    private func changeDefaultRuntime(_ id: UUID) async throws {
        accept(try await siteChanges.apply(.defaultRuntime(id)))
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
            let inspected = try await DevelopmentRuntimeProvider().inspectCaddy(binary: runtime.executable,
                workDirectory: JSONConfigurationStore.applicationDirectory.appendingPathComponent("runtime-inspection"))
            accept(try await siteChanges.apply(.caddy(inspected)))
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
            self.accept(try await self.siteChanges.apply(.caddy(runtime)))
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
        perform { self.preparedSiteChange = nil; self.pendingSetup = try await self.prepareSetup() }
    }

    func approveHTTPS(_ setup: HTTPSSetup) {
        perform(cancellable: false, message: "Applying HTTPS setup. Complete or cancel the macOS approval prompt…") {
            try await self.helper.registerAfterApproval()
            if let change = self.preparedSiteChange {
                self.configuration = try await self.siteChanges.approve(change)
                if let selection = self.preparedSelection { self.selectedSiteID = selection }
                self.preparedSiteChange = nil; self.preparedSelection = nil
            } else {
                guard Set(setup.request.hostnames) == Set(self.enabledSites.map(\.hostname)) else {
                    throw JerdError.invalid("The enabled sites changed. Review HTTPS setup again.")
                }
                try await self.environment.apply(setup)
                self.systemStatus = try await self.helper.status()
                try await self.startEnvironment()
            }
            self.systemStatus = try await self.helper.status()
            self.pendingSetup = nil
        }
    }

    func start() { perform(message: "Checking PHP-FPM and HTTPS…") { try await self.startEnvironment() } }
    func stop() {
        guard canStop else { return }
        let previous = work
        if canCancelWork { previous?.cancel() }
        updates.cancelInstall()
        workGeneration += 1
        let generation = workGeneration
        isBusy = true; stopInProgress = true
        operationMessage = canCancelWork ? "Stopping sites…" : "Waiting for system setup. Complete or cancel the macOS approval prompt…"
        errorMessage = nil
        work = Task {
            defer { stopInProgress = false; finishWork(generation) }
            await siteChanges.requestStop()
            await previous?.value
            await waitForBackgroundWork()
            operationMessage = "Stopping PHP-FPM and Caddy…"
            await stopEnvironment()
        }
    }

    func removeSystemSetup() {
        perform(cancellable: false, message: "Removing HTTPS setup. Complete or cancel the macOS approval prompt…") {
            await self.stopEnvironment()
            try await self.environment.removeSetup()
            self.systemStatus = SystemSetupStatus()
            try await self.helper.unregisterAfterCleanup()
        }
    }

    func inspectSystemRecovery() {
        perform {
            if await self.helper.isEnabled() { self.systemStatus = try await self.helper.status() }
        }
    }

    func recoverSystemSetup(_ report: SystemRecoveryStatus, action: SystemRecoveryAction) {
        perform(cancellable: false, message: "Recovering HTTPS setup. Complete or cancel the macOS approval prompt…") {
            await self.stopEnvironment()
            do { try await self.helper.recover(report, action: action) }
            catch {
                self.systemStatus = (try? await self.helper.status()) ?? self.systemStatus
                throw error
            }
            self.systemStatus = try await self.helper.status()
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
        environmentState = .starting
        do {
            try await environment.ensure(WebConfiguration(sites: selections, caddy: caddy))
            environmentState = await environment.state
            runningSiteIDs = Set(sites.map(\.id))
        } catch {
            environmentState = await environment.state
            throw error
        }
    }

    private func refreshEnvironment() async {
        let snapshot = await environment.snapshot()
        applyEnvironment(snapshot.state, siteIDs: snapshot.siteIDs)
    }

    // Polling runs every 500 ms. Assign only changed values, because each
    // assignment to an observed property invalidates the views that read it.
    private func applyEnvironment(_ state: EnvironmentState, siteIDs: Set<UUID>) {
        let running = state == .running ? siteIDs : []
        if environmentState != state { environmentState = state }
        if runningSiteIDs != running { runningSiteIDs = running }
    }

    func inspectRecovery() {
        perform(message: "Inspecting saved service records and backups…") {
            if await self.helper.isEnabled() { self.systemStatus = try await self.helper.status() }
            self.processFindings = try await self.processRecovery.inspect()
            self.retainedBackups = try await self.backupRetention.inspect()
        }
    }

    func recoverProcess(_ id: String) {
        perform(cancellable: false, message: "Waiting for the saved service to stop safely…") {
            do { try await self.processRecovery.recover(id) }
            catch { self.processFindings = try await self.processRecovery.inspect(); throw error }
            self.processFindings = try await self.processRecovery.inspect()
        }
    }

    func removeBackup(_ id: String) {
        perform(message: "Removing the selected backup…") {
            try await self.backupRetention.remove(id)
            self.retainedBackups = try await self.backupRetention.inspect()
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
        operationMessage = canCancelWork ? "Cancelling preparation…" : "Waiting for system setup. Complete or cancel the macOS approval prompt…"
        if canCancelWork { work?.cancel() }
        await siteChanges.requestStop()
        await work?.value
        operationMessage = "Finishing runtime changes…"
        await updates.finishBeforeQuit()
        operationMessage = "Stopping storage…"
        guard await storage.shutdown() else {
            isShuttingDown = false
            operationMessage = nil
            updates.resumeAfterCancelledQuit()
            selectedSection = .storage
            errorMessage = "Storage could not stop safely. Jerd will remain open. Retry Stop in Storage."
            return false
        }
        operationMessage = "Stopping mail…"
        guard await mail.shutdown() else {
            isShuttingDown = false
            operationMessage = nil
            updates.resumeAfterCancelledQuit()
            storage.resumeAfterCancelledQuit()
            selectedSection = .mail
            errorMessage = "The mail service could not stop safely. Jerd will remain open. Retry Stop in Mail."
            return false
        }
        operationMessage = "Stopping databases safely…"
        guard await databases.shutdown() else {
            isShuttingDown = false
            operationMessage = nil
            updates.resumeAfterCancelledQuit()
            storage.resumeAfterCancelledQuit()
            mail.resumeAfterCancelledQuit()
            errorMessage = "A database service could not stop safely. Jerd will remain open. Check Databases and retry Stop."
            return false
        }
        operationMessage = "Stopping PHP-FPM and Caddy…"
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
