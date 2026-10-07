import Foundation
import JerdMail
import JerdServiceKit
import Observation

/// The Mail section: the one Mailpit inbox, its ports, the Laravel settings, and a test email.
/// One change runs at a time: a page operation or a port change. A failure of the service itself shows as its state; any other
/// failure shows once, as the page banner.
@MainActor
@Observable
public final class MailModel {
    public internal(set) var snapshot = MailSnapshot(settings: MailSettings(), state: .stopped)
    public internal(set) var files: ServiceFiles?
    public internal(set) var loadState: ServiceLoadState = .loading
    /// Why the bundled runtime setup at launch failed, or nil. The page shows it while the
    /// runtime is still missing.
    public internal(set) var runtimeSetupFailure: String?
    public internal(set) var operation: OperationState = .idle
    /// The confirmation of the last test email, until the next operation.
    public internal(set) var testResult: String?
    public internal(set) var isShuttingDown = false
    /// The open ports sheet, or nil.
    public var portsDraft: PortsDraft?
    public internal(set) var portsOperation: OperationState = .idle
    /// The pinned Mailpit that Jerd can install on demand, or nil.
    public internal(set) var runtimeOffer: ServiceRuntimeOffer?
    /// The one Mailpit installation that runs, or nil.
    public internal(set) var runtimeInstallation: ServiceRuntimeInstallation?
    /// Why the last Mailpit installation of the page failed, or that it was cancelled.
    public internal(set) var runtimeNotice: ServiceRuntimeNotice?
    /// The installation that waits for the user to confirm it.
    public var pendingRuntimeInstall: ServiceRuntimeRequest?

    /// Shows another place in the window, for example Runtimes. `AppState` sets it.
    @ObservationIgnored public var navigate: (@MainActor (Destination) -> Void)?
    /// Shows the Mail page in the front window, so a request from the card or the menu bar shows
    /// its confirmation there. `AppState` sets it.
    @ObservationIgnored public var presentPage: (@MainActor () -> Void)?
    /// Why Install waits: another page installs a runtime now; nil when none does. `AppState` sets
    /// it: the pages share one installer.
    @ObservationIgnored public var runtimeInstallElsewhere: (@MainActor () -> String?)?
    /// The Mailpit installation of the page. Cancel and Quit stop it before its final rename.
    @ObservationIgnored var runtimeInstallTask: Task<Void, Never>?
    @ObservationIgnored let port: any MailPort
    @ObservationIgnored let clipboard: Clipboard
    @ObservationIgnored let workspace: any WorkspaceOpening
    @ObservationIgnored let running = RunningTasks()
    /// The suggestion or save of the ports sheet. Cancel asks it to stop; it keeps mail locked
    /// until it ends.
    @ObservationIgnored var portsTask: Task<Void, Never>?

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
    public var isBusy: Bool { operation.isWorking || portsOperation.isWorking || runtimeInstallation != nil }

    /// True when the user can start a change now.
    public var canChange: Bool {
        loadState.isLoaded && !isBusy && !isShuttingDown && !state.isBusy
    }

    /// Start needs a runtime, or a pinned Mailpit that it installs first.
    public var canStart: Bool {
        canChange && !state.offersStop && (hasRuntime || (runtimeOffer != nil && runtimeInstallElsewhere?() == nil))
    }

    /// True when Start installs Mailpit first.
    public var startInstallsRuntime: Bool { !hasRuntime && runtimeOffer != nil }
    public var canStop: Bool { canChange && state.offersStop }
    public var canOpenInbox: Bool { state.isRunning && !isShuttingDown }
    public var canSendTestEmail: Bool { canChange && state.isRunning }
    /// Why Open Inbox is off, or nil: Mailpit is not installed yet, or mail does not run.
    public var inboxUnavailableReason: String? {
        canOpenInbox ? nil : unavailableReason(to: "open the inbox")
    }
    /// Why Send Test Email is off, or nil, with the same rule as Open Inbox.
    public var testEmailUnavailableReason: String? {
        canSendTestEmail ? nil : unavailableReason(to: "send a test email")
    }
    /// The registration of Mailpit chooses the ports, so they change only after it, and only while
    /// no process runs.
    public var canEditPorts: Bool { canChange && hasRuntime && !state.offersStop }
    /// The settings come from the saved ports, so the copy never waits for other work.
    public var canCopyEnvironment: Bool { loadState.isLoaded && !isShuttingDown && hasRuntime }

    /// Reads the settings once at launch.
    public func load() async {
        do {
            apply(try await port.load())
            runtimeSetupFailure = await port.runtimeSetupFailure()
            runtimeOffer = await port.runtimeOffer()
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

    /// The step that an inbox action needs first, for example `Start mail to open the inbox.`
    private func unavailableReason(to action: String) -> String? {
        if loadState.isLoaded, !hasRuntime { return "Install Mailpit, then start mail to \(action)." }
        return state.isRunning ? nil : "Start mail to \(action)."
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
