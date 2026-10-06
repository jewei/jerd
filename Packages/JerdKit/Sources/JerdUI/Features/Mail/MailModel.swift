import Foundation
import JerdMail
import JerdServiceKit
import Observation

/// The Mail section: the one Mailpit inbox, its ports, the Laravel settings, and a test email.
/// One operation runs at a time. A failure of the service itself shows as its state; any other
/// failure shows once, as the page banner.
@MainActor
@Observable
public final class MailModel {
    public internal(set) var snapshot = MailSnapshot(settings: MailSettings(), state: .stopped)
    public internal(set) var files: ServiceFiles?
    public internal(set) var loadState: ServiceLoadState = .loading
    public internal(set) var operation: OperationState = .idle
    /// The confirmation of the last test email, until the next operation.
    public internal(set) var testResult: String?
    public internal(set) var isShuttingDown = false
    /// The open ports sheet, or nil.
    public var portsDraft: PortsDraft?
    public internal(set) var portsOperation: OperationState = .idle

    /// Shows another place in the window, for example Runtimes. `AppState` sets it.
    @ObservationIgnored public var navigate: (@MainActor (Destination) -> Void)?
    @ObservationIgnored let port: any MailPort
    @ObservationIgnored let clipboard: Clipboard
    @ObservationIgnored let workspace: any WorkspaceOpening
    @ObservationIgnored var currentTask: Task<Void, Never>?

    public init(port: any MailPort, clipboard: Clipboard, workspace: any WorkspaceOpening) {
        self.port = port
        self.clipboard = clipboard
        self.workspace = workspace
    }

    static let testCaptured = "Test email captured. Open the inbox to view it."
    static let loadFailed = "Mail settings could not be loaded. The existing file was preserved."

    public var state: ServiceState { snapshot.state }
    public var settings: MailSettings { snapshot.settings }
    public var hasRuntime: Bool { settings.runtime != nil }

    /// True while any work of this feature runs, so other pages and Quit can wait for it.
    public var isBusy: Bool { operation.isWorking || portsOperation.isWorking }

    /// True when the user can start a change now.
    public var canChange: Bool {
        loadState.isLoaded && !operation.isWorking && !isShuttingDown && !state.isBusy
    }

    public var canStart: Bool { canChange && hasRuntime && !state.offersStop }
    public var canStop: Bool { canChange && state.offersStop }
    public var canOpenInbox: Bool { state.isRunning && !isShuttingDown }
    public var canSendTestEmail: Bool { canChange && state.isRunning }
    /// Ports change only while no process runs.
    public var canEditPorts: Bool { canChange && !state.offersStop }

    /// Reads the settings once at launch.
    public func load() async {
        do {
            apply(try await port.load())
            loadState = .loaded
            await refreshFiles()
        } catch {
            loadState = .failed(message: "\(Self.loadFailed) \(ErrorText.message(for: error))")
        }
    }

    /// Reads the state for the poller. Only changed values are applied.
    public func refresh() async {
        guard loadState.isLoaded else { return }
        apply(await port.snapshot())
        await refreshFiles()
    }

    /// Removes the failure banner.
    public func dismissFailure() {
        if operation.failureMessage != nil { operation = .idle }
    }

    func apply(_ next: MailSnapshot) {
        if next != snapshot { snapshot = next }
    }

    private func refreshFiles() async {
        let next = await port.files()
        if next != files { files = next }
    }

    /// Runs one operation. A failure that the service state already shows is not repeated in
    /// the banner.
    func perform(
        _ message: String, _ work: @escaping @MainActor (MailModel) async throws -> Void
    )
        -> Task<Void, Never>?
    {
        guard canChange else { return nil }
        operation = .working(message)
        testResult = nil
        let task = Task {
            var failure: String?
            do {
                try await work(self)
            } catch {
                failure = ErrorText.message(for: error)
            }
            await refresh()
            operation = failure.flatMap { state.needsAttention ? nil : OperationState.failed(message: $0) } ?? .idle
        }
        currentTask = task
        return task
    }
}
