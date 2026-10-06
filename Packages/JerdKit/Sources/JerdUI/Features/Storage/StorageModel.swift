import Foundation
import JerdServiceKit
import JerdStorage
import Observation

/// The Storage section: the one RustFS service, its buckets, credentials, ports, and Laravel
/// settings. One change runs at a time: a page operation, a bucket save, or a port change.
/// Copies never wait for it (spec E 7.8.4).
@MainActor
@Observable
public final class StorageModel {
    public internal(set) var snapshot = StorageSnapshot(
        settings: StorageSettings(), state: .stopped, availableBuckets: [])
    public internal(set) var files: ServiceFiles?
    public internal(set) var loadState: ServiceLoadState = .loading
    public internal(set) var operation: OperationState = .idle
    public internal(set) var isShuttingDown = false
    /// The open Add Bucket sheet, or nil.
    public var bucketDraft: BucketDraft?
    public internal(set) var bucketOperation: OperationState = .idle
    /// The open ports sheet, or nil.
    public var portsDraft: PortsDraft?
    public internal(set) var portsOperation: OperationState = .idle

    /// Shows another place in the window, for example a new bucket. `AppState` sets it.
    @ObservationIgnored public var navigate: (@MainActor (Destination) -> Void)?
    @ObservationIgnored let port: any StoragePort
    @ObservationIgnored let clipboard: Clipboard
    @ObservationIgnored let workspace: any WorkspaceOpening
    @ObservationIgnored let running = RunningTasks()
    /// The save of the Add Bucket sheet. Cancel asks it to stop; it keeps storage locked until it ends.
    @ObservationIgnored var bucketTask: Task<Void, Never>?
    /// The suggestion or save of the ports sheet, with the same rule as `bucketTask`.
    @ObservationIgnored var portsTask: Task<Void, Never>?

    public init(port: any StoragePort, clipboard: Clipboard, workspace: any WorkspaceOpening) {
        self.port = port
        self.clipboard = clipboard
        self.workspace = workspace
    }

    static let loadFailed = "Storage settings could not be loaded. The existing file was preserved."

    public var state: ServiceState { snapshot.state }
    public var settings: StorageSettings { snapshot.settings }
    public var buckets: [StorageBucket] { settings.buckets }
    public var hasRuntime: Bool { settings.runtime != nil }

    /// True while any work of this feature runs, so other pages and Quit can wait for it.
    public var isBusy: Bool { operation.isWorking || bucketOperation.isWorking || portsOperation.isWorking }

    /// True when a change can start now: nothing else of this feature runs.
    public var canChange: Bool {
        loadState.isLoaded && !isBusy && !isShuttingDown && !state.isBusy
    }

    public var canStart: Bool { canChange && hasRuntime && !state.offersStop }
    public var canStop: Bool { canChange && state.offersStop }
    public var canOpenConsole: Bool { state.isRunning && !isShuttingDown }
    /// Save starts storage when needed, so Add needs only a runtime and no other work.
    public var canAddBucket: Bool { canChange && hasRuntime }
    public var canEditPorts: Bool { canChange && !state.offersStop }
    /// Credentials exist after the first start created the data folder.
    public var hasCredentials: Bool { files?.hasDataFolder == true }

    /// The registered bucket with `name`.
    public func bucket(named name: String) -> StorageBucket? { settings.bucket(name) }

    public func load() async {
        do {
            apply(try await port.load())
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

    func apply(_ next: StorageSnapshot) {
        if next != snapshot { snapshot = next }
    }

    private func refreshFiles() async {
        let next = await port.files()
        if next != files { files = next }
    }

    /// Runs one page operation. A failure that the service state already shows is not repeated.
    func perform(
        _ message: String, _ work: @escaping @MainActor (StorageModel) async throws -> Void
    )
        -> Task<Void, Never>?
    {
        guard canChange else { return nil }
        operation = .working(message)
        return running.run { [self] in
            var failure: String?
            do {
                try await work(self)
            } catch {
                failure = ErrorText.message(for: error)
            }
            await refresh()
            operation = failure.flatMap { state.needsAttention ? nil : OperationState.failed(message: $0) } ?? .idle
        }
    }
}
