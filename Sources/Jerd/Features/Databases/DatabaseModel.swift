import AppKit
import Observation
import JerdCore

@MainActor @Observable
final class DatabaseModel {
    var configuration = DatabaseConfiguration()
    var retained: [RetainedDatabase] = []
    var statuses: [UUID: DatabaseStatus] = [:]
    var selectedID: UUID?
    var errorMessage: String?
    var runtimeMessage = "Preparing database runtimes…"
    var isLoading = false
    var isLoaded = false
    var isSaving = false
    var isShuttingDown = false
    var busyIDs: Set<UUID> = []
    let directory = JSONConfigurationStore.applicationDirectory.appendingPathComponent("databases")
    @ObservationIgnored private lazy var manager = DatabaseManager(directory: directory)
    private var settingsTask: Task<Void, Never>?
    private var work: [UUID: Task<Void, Never>] = [:]
    private var monitor: Task<Void, Never>?

    var selected: DatabaseService? { configuration.services.first { $0.id == selectedID } }
    func status(_ service: DatabaseService) -> DatabaseStatus { statuses[service.id] ?? DatabaseStatus() }
    func paths(_ service: DatabaseService) -> DatabasePaths { DatabasePaths(directory: directory, serviceID: service.id) }
    func runtime(_ service: DatabaseService) -> DatabaseRuntime? { try? configuration.runtime(for: service) }
    func isBusy(_ service: DatabaseService) -> Bool {
        isLoading || isShuttingDown || busyIDs.contains(service.id) || status(service).state.isBusy
    }

    func load() {
        guard !isLoading, !isSaving, !isShuttingDown else { return }
        isLoading = true
        errorMessage = nil
        settingsTask = Task {
            defer { isLoading = false }
            do {
                configuration = try await manager.load()
                isLoaded = true
                selectedID = selectedID ?? configuration.services.first?.id
                let installedEngines = Set(configuration.runtimes.map(\.engine))
                if installedEngines.count < DatabaseEngine.allCases.count, let resources = Bundle.main.resourceURL {
                    do {
                        let runtimes = try await BundledDatabaseRuntimes().install(
                            from: resources.appendingPathComponent("DatabaseRuntimes"),
                            into: JSONConfigurationStore.applicationDirectory.appendingPathComponent("database-runtimes"), excluding: installedEngines)
                        try await manager.registerRuntimes(runtimes)
                        runtimeMessage = "MySQL, PostgreSQL, and Redis are installed. Each service has its own data folder."
                    } catch {
                        runtimeMessage = "Database runtime setup failed: \(error.localizedDescription)"
                    }
                }
                if runtimeMessage == "Preparing database runtimes…" { runtimeMessage = "Database runtimes are installed. Each service has its own data folder." }
                await refresh()
                startMonitoring()
            } catch {
                errorMessage = error.localizedDescription
                runtimeMessage = "Database settings could not be loaded. The existing file was preserved."
            }
        }
    }

    func suggestPort(_ engine: DatabaseEngine) async throws -> UInt16 { try await manager.suggestedPort(for: engine) }

    func registerUpdatedRuntime(_ runtime: DatabaseRuntime) async throws {
        guard isLoaded, !isLoading, !isSaving, !isShuttingDown else { throw JerdError.unavailable("Wait for database settings to finish loading or saving.") }
        isSaving = true; defer { isSaving = false }
        try await manager.registerRuntimes([runtime])
        await refresh()
    }

    func create(name: String, runtimeID: String, port: UInt16, completion: @escaping () -> Void) {
        guard !isSaving, !isLoading, !isShuttingDown else { return }
        isSaving = true
        errorMessage = nil
        settingsTask = Task {
            defer { isSaving = false }
            do {
                let service = try await manager.add(name: name, runtimeID: runtimeID, port: port)
                await refresh()
                selectedID = service.id
                completion()
                start(service)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func edit(_ service: DatabaseService, completion: @escaping () -> Void) {
        change(service) {
            try await self.manager.edit(service)
            completion()
        }
    }
    func remove(_ service: DatabaseService) {
        change(service) {
            try await self.manager.remove(service.id)
            if self.selectedID == service.id { self.selectedID = nil }
        }
    }
    private func change(_ service: DatabaseService, action: @escaping @MainActor () async throws -> Void) {
        guard !isSaving, !isBusy(service) else { return }
        isSaving = true
        busyIDs.insert(service.id)
        errorMessage = nil
        settingsTask = Task {
            defer { isSaving = false; busyIDs.remove(service.id) }
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
            await refresh()
        }
    }

    func inspectRetained() {
        guard !isLoading, !isSaving, !isShuttingDown else { return }
        isSaving = true
        settingsTask = Task {
            defer { isSaving = false }
            do { retained = try await manager.retainedDatabases() }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func restore(_ item: RetainedDatabase, name: String, port: UInt16, completion: @escaping () -> Void) {
        guard !isLoading, !isSaving, !isShuttingDown else { return }
        isSaving = true; errorMessage = nil
        settingsTask = Task {
            defer { isSaving = false }
            do {
                let service = try await manager.restoreRegistration(item.id, name: name, port: port)
                await refresh()
                selectedID = service.id
                retained = try await manager.retainedDatabases()
                completion()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func start(_ service: DatabaseService) {
        perform(service) { try await self.manager.start(service.id) }
    }
    func stop(_ service: DatabaseService) {
        perform(service) { try await self.manager.stop(service.id) }
    }
    private func perform(_ service: DatabaseService, action: @escaping @MainActor () async throws -> Void) {
        guard !isBusy(service), isLoaded else { return }
        busyIDs.insert(service.id)
        errorMessage = nil
        work[service.id] = Task {
            defer { busyIDs.remove(service.id); work[service.id] = nil }
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
            await refresh()
        }
    }

    func copyConnection(_ service: DatabaseService, passwordOnly: Bool = false) {
        Task {
            do {
                let connection = try await manager.connection(for: service.id)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(passwordOnly ? connection.password : connection.environment, forType: .string)
            } catch { errorMessage = error.localizedDescription }
        }
    }
    func revealData(_ service: DatabaseService) {
        if !NSWorkspace.shared.open(paths(service).data) { errorMessage = "Start the service once to create its data folder." }
    }
    func openLog(_ service: DatabaseService) {
        if !NSWorkspace.shared.open(paths(service).log) { errorMessage = "The service log is not available yet." }
    }

    private func refresh() async {
        let snapshot = await manager.snapshot()
        configuration = snapshot.configuration
        statuses = snapshot.statuses
    }
    private func startMonitoring() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }
    func shutdown() async -> Bool {
        isShuttingDown = true
        await settingsTask?.value
        for task in Array(work.values) { await task.value }
        do {
            try await manager.stopAll()
            monitor?.cancel()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            isShuttingDown = false
            await refresh()
            return false
        }
    }
}
