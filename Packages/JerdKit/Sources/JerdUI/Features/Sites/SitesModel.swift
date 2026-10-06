import Foundation
import JerdWeb
import Observation

/// The Sites section: the registered sites, the web environment, the HTTPS setup, and the
/// tunnels. One site operation runs at a time, because every change is one site transaction.
/// Each error shows once: in the sheet that caused it, or on this page.
@MainActor
@Observable
public final class SitesModel {
    public internal(set) var configuration = AppConfiguration()
    public internal(set) var environment = EnvironmentSnapshot(state: .stopped, siteIDs: [])
    /// What the helper reports, or nil before the first read or when the read failed.
    public internal(set) var setup: HTTPSSetupStatus?
    /// Why the HTTPS setup could not be read, shown in the system setup banner.
    public internal(set) var setupReadFailure: String?
    /// True after the saved sites were read.
    public internal(set) var isLoaded = false
    public internal(set) var operation: OperationState = .idle
    /// The editor or the HTTPS approval.
    public var sheet: SitesSheet?
    /// The failure of the last approval, shown inside the approval sheet.
    public internal(set) var approvalFailure: String?
    /// The step that waits for confirmation. The page shows it as a dialog.
    public var confirmation: SitesConfirmation?
    public internal(set) var isShuttingDown = false
    public let tunnels: TunnelsModel
    /// The window services. `AppState` connects them after it builds the model.
    @ObservationIgnored public var shell = SitesShell.detached

    @ObservationIgnored let port: any SitesPort
    @ObservationIgnored let panels: any FilePanelPresenting
    @ObservationIgnored let workspace: any WorkspaceOpening
    @ObservationIgnored let clipboard: Clipboard
    @ObservationIgnored var currentWork: Task<Void, Never>?
    /// The shared lock: every site and HTTPS change holds it, and the quit waits for it.
    @ObservationIgnored let lock: OperationLock

    public init(
        port: any SitesPort, tunnels: TunnelsModel, panels: any FilePanelPresenting,
        workspace: any WorkspaceOpening, clipboard: Clipboard, lock: OperationLock = OperationLock()
    ) {
        self.lock = lock
        self.port = port
        self.tunnels = tunnels
        self.panels = panels
        self.workspace = workspace
        self.clipboard = clipboard
    }

    public var sites: [Site] { configuration.sites }

    /// The site with `id`, if it is still registered.
    public func site(_ id: UUID) -> Site? {
        configuration.sites.first { $0.id == id }
    }

    /// True while a site operation runs or Jerd quits. Every site action is then disabled.
    public var isBusy: Bool { operation.isWorking || isShuttingDown }

    /// True when a change can start: the sites are loaded, no site work runs, and no other
    /// page holds the shared lock or quits.
    public var canChange: Bool { isLoaded && !isBusy && lock.isFree }

    /// Reads the saved sites, the environment, and the HTTPS setup, then the tunnels.
    public func launch() async {
        await loadSites()
        await tunnels.launch()
    }

    /// Reads the saved sites again after a failed load.
    @discardableResult
    public func retryLoad() -> Task<Void, Never>? {
        guard !isLoaded, !isBusy else { return nil }
        let task = Task { await loadSites() }
        currentWork = task
        return task
    }

    /// Reads the environment. The poller calls it; it changes only what changed. The tunnels
    /// have their own polling task.
    public func refresh() async {
        let latest = await port.environment()
        if latest != environment { environment = latest }
    }

    /// Removes the failure banner.
    public func dismissFailure() {
        if operation.failureMessage != nil { operation = .idle }
    }

    private func loadSites() async {
        operation = .working("Checking settings…")
        do {
            configuration = try await port.loadConfiguration()
            isLoaded = true
            operation = .idle
        } catch {
            operation = .failed(
                message: "Site settings could not be loaded. The existing file was preserved. "
                    + ErrorText.message(for: error))
        }
        environment = await port.environment()
        await readSetup()
    }

    /// Reads the HTTPS setup. After a failed read no hostname counts as approved, and the
    /// page says why; the next operation reads it again.
    func readSetup() async {
        do {
            setup = try await port.setupStatus()
            setupReadFailure = nil
        } catch {
            setup = nil
            setupReadFailure = ErrorText.message(for: error)
        }
    }

    /// Reads the environment and the HTTPS setup after an operation.
    func settle() async {
        environment = await port.environment()
        await readSetup()
    }

    /// Applies the result of a change: the saved configuration, or the approval sheet.
    func accept(_ outcome: SiteChangeOutcome) {
        switch outcome {
        case .committed(let saved):
            configuration = saved
        case .needsApproval(let approval):
            approvalFailure = nil
            sheet = .approval(approval)
        }
    }
}
