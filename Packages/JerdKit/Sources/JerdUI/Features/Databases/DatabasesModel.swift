import Foundation
import JerdDatabases
import JerdServiceKit
import Observation

/// The Databases section: independent MySQL, PostgreSQL, and Redis services. Each service starts
/// and stops on its own; registry changes (add, edit, remove, restore) run one at a time.
@MainActor
@Observable
public final class DatabasesModel {
    public internal(set) var snapshot = DatabaseSnapshot(configuration: DatabaseConfiguration(), states: [:])
    public internal(set) var files: [UUID: ServiceFiles] = [:]
    public internal(set) var loadState: ServiceLoadState = .loading
    /// Why the bundled runtime setup at launch failed, or nil. The page shows it while the
    /// runtime is still missing.
    public internal(set) var runtimeSetupFailure: String?
    /// Registry changes and page failures.
    public internal(set) var operation: OperationState = .idle
    /// Services with a start or stop in progress.
    public internal(set) var busyServices: Set<UUID> = []
    public internal(set) var isShuttingDown = false
    public var sheet: DatabasesSheet?
    public var editor: DatabaseDraft?
    public internal(set) var editorOperation: OperationState = .idle
    public internal(set) var retained: [RetainedDatabase] = []
    public internal(set) var retainedOperation: OperationState = .idle
    public var restoreDraft: RestoreDraft?
    public internal(set) var restoreOperation: OperationState = .idle
    /// The service that waits for the remove confirmation.
    public var pendingRemoval: DatabaseService?

    /// Shows another place in the window, for example a new service. `AppState` sets it.
    @ObservationIgnored public var navigate: (@MainActor (Destination) -> Void)?
    /// The service that the Databases page shows. `AppState` sets it; a copy uses it to drop a
    /// value that arrives after the user selected another service.
    @ObservationIgnored public var selectedService: (@MainActor () -> UUID?)?
    @ObservationIgnored let port: any DatabasesPort
    @ObservationIgnored let clipboard: Clipboard
    @ObservationIgnored let workspace: any WorkspaceOpening
    @ObservationIgnored let running = RunningTasks()
    /// The save of the editor sheet. Cancel asks it to stop; it keeps the registry locked until it ends.
    @ObservationIgnored var editorTask: Task<Void, Never>?
    /// The save of the restore sheet, with the same rule as `editorTask`.
    @ObservationIgnored var restoreTask: Task<Void, Never>?

    public init(port: any DatabasesPort, clipboard: Clipboard, workspace: any WorkspaceOpening) {
        self.port = port
        self.clipboard = clipboard
        self.workspace = workspace
    }

    static let loadFailed = "Database settings could not be loaded. The existing file was preserved."

    public var configuration: DatabaseConfiguration { snapshot.configuration }
    public var services: [DatabaseService] { configuration.services }

    public func state(of id: UUID) -> ServiceState { snapshot.state(of: id) }
    public func service(_ id: UUID) -> DatabaseService? { configuration.service(id) }
    public func runtime(of service: DatabaseService) -> DatabaseRuntime? { try? configuration.runtime(for: service) }

    /// The engines with at least one installed runtime, in engine order.
    public var availableEngines: [DatabaseEngine] {
        DatabaseEngine.allCases.filter { engine in configuration.runtimes.contains { $0.engine == engine } }
    }

    /// The failed bundled setup while an engine still has no runtime. An engine installed later
    /// in Runtimes ends the problem, so the banner goes away with it.
    public var visibleRuntimeSetupFailure: String? {
        availableEngines.count < DatabaseEngine.allCases.count ? runtimeSetupFailure : nil
    }

    /// True while any database work runs, so other pages and Quit can wait for it.
    public var isBusy: Bool {
        operation.isWorking || editorOperation.isWorking || restoreOperation.isWorking || !busyServices.isEmpty
    }

    /// True when a registry change can start now.
    public var canChangeRegistry: Bool {
        loadState.isLoaded && !operation.isWorking && !isShuttingDown && !editorOperation.isWorking
            && !restoreOperation.isWorking
    }

    public var canAdd: Bool { canChangeRegistry && !availableEngines.isEmpty }

    /// True when `id` can start or stop now.
    public func canControl(_ id: UUID) -> Bool {
        loadState.isLoaded && !isShuttingDown && !operation.isWorking && !busyServices.contains(id)
            && !state(of: id).isBusy
    }

    public func canStart(_ id: UUID) -> Bool {
        guard let service = service(id) else { return false }
        return canControl(id) && runtime(of: service) != nil && !state(of: id).offersStop
    }

    public func canStop(_ id: UUID) -> Bool { canControl(id) && state(of: id).offersStop }

    /// Edit needs a stopped service, because the data folder is in use while it runs.
    public func canEdit(_ id: UUID) -> Bool {
        canChangeRegistry && canControl(id) && !state(of: id).offersStop
    }

    public func canRemove(_ id: UUID) -> Bool { canChangeRegistry && canControl(id) }

    public func load() async {
        do {
            apply(try await port.load())
            runtimeSetupFailure = await port.runtimeSetupFailure()
            loadState = .loaded
            await refreshFiles()
        } catch {
            loadState = .failed(message: "\(Self.loadFailed) \(ErrorText.message(for: error))")
        }
    }

    public func refresh() async {
        guard loadState.isLoaded else { return }
        apply(await port.snapshot())
        await refreshFiles()
    }

    public func dismissFailure() {
        if operation.failureMessage != nil { operation = .idle }
    }

    func apply(_ next: DatabaseSnapshot) {
        if next != snapshot { snapshot = next }
    }

    private func refreshFiles() async {
        var next: [UUID: ServiceFiles] = [:]
        for service in services {
            next[service.id] = await port.files(for: service.id)
        }
        if next != files { files = next }
    }

    /// Runs work whose task Quit waits for.
    func track(_ work: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        running.run(work)
    }
}
