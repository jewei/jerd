import Foundation
import JerdTunnels
import Observation

/// The Cloudflare tunnels inside the Sites section. One edit runs at a time; each Stop runs on
/// its own, so a slow connector never blocks another. Save never connects.
@MainActor
@Observable
public final class TunnelsModel {
    public internal(set) var configuration = TunnelConfiguration()
    public internal(set) var snapshots: [UUID: TunnelSnapshot] = [:]
    public internal(set) var isLoaded = false
    /// Why the settings could not be loaded. The file stays as it is.
    public internal(set) var loadFailure: String?
    public internal(set) var operation: OperationState = .idle
    public internal(set) var stoppingIDs: Set<UUID> = []
    /// Tunnels that could not connect when Jerd opened, with the reason.
    public internal(set) var startupFailures: [UUID: String] = [:]
    /// Connectors that did not stop, with the reason, shown on their tunnel page.
    public internal(set) var stopFailures: [UUID: String] = [:]
    public internal(set) var isShuttingDown = false
    public var sheet: TunnelsSheet?
    public var confirmation: TunnelConfirmation?
    /// Navigation and the window, shared with the Sites model.
    @ObservationIgnored let shell: SitesShell

    @ObservationIgnored let port: any TunnelsPort
    @ObservationIgnored let panels: any FilePanelPresenting
    @ObservationIgnored let workspace: any WorkspaceOpening
    @ObservationIgnored let clipboard: Clipboard
    @ObservationIgnored var currentWork: Task<Void, Never>?
    @ObservationIgnored var stopWork: [UUID: Task<Void, Never>] = [:]

    public init(
        port: any TunnelsPort, panels: any FilePanelPresenting, workspace: any WorkspaceOpening, clipboard: Clipboard,
        shell: SitesShell
    ) {
        self.shell = shell
        self.port = port
        self.panels = panels
        self.workspace = workspace
        self.clipboard = clipboard
    }

    public var registrations: [TunnelRegistration] { configuration.tunnels }

    public func registration(_ id: UUID) -> TunnelRegistration? {
        configuration.registration(id)
    }

    public func state(of id: UUID) -> TunnelState {
        snapshots[id]?.state ?? .stopped
    }

    /// True while a connector runs, a Connect or Stop runs, or Jerd still owns its process.
    public func isActive(_ id: UUID) -> Bool {
        state(of: id).isActive || snapshots[id]?.processID != nil
    }

    /// The next step of a tunnel page: open a running connector, edit a failed one or one
    /// whose settings need an edit, else connect.
    public func nextStep(for id: UUID) -> TunnelNextStep {
        if isActive(id) { return .open }
        if state(of: id).failureMessage != nil || snapshots[id]?.settingsIssue != nil { return .edit }
        return .connect
    }

    public var connectedCount: Int {
        registrations.filter { state(of: $0.id) == .connected }.count
    }

    /// True while an edit runs or Jerd quits.
    public var isBusy: Bool { operation.isWorking || isShuttingDown }

    /// True when an edit can start.
    public var canChange: Bool { isLoaded && !isBusy }

    public func canStop(_ id: UUID) -> Bool {
        isLoaded && !isShuttingDown && !stoppingIDs.contains(id) && isActive(id)
    }

    /// The cloudflared line of the detail page.
    public var runtimeMessage: String {
        configuration.runtime.map { "cloudflared \($0.version) is installed." }
            ?? "Install cloudflared in Runtimes, or choose a trusted local executable."
    }

    /// Loads the settings, then connects the tunnels with "Start when Jerd opens".
    public func launch() async {
        await load()
        guard isLoaded, !isShuttingDown else { return }
        do {
            let failures = try await port.connectStartupTunnels()
            startupFailures = Dictionary(failures.map { ($0.id, $0.message) }) { first, _ in first }
        } catch {
            operation = .failed(message: ErrorText.message(for: error))
        }
        await refresh()
    }

    /// Reads the settings again after a failed load.
    public func retryLoad() async {
        guard !isLoaded, !isBusy else { return }
        await load()
    }

    /// Reads the settings and the connector states. It changes only what changed.
    public func refresh() async {
        guard isLoaded else { return }
        let latestConfiguration = await port.configuration()
        let latest = Dictionary(await port.snapshots().map { ($0.registration.id, $0) }) { first, _ in first }
        if latestConfiguration != configuration { configuration = latestConfiguration }
        if latest != snapshots { snapshots = latest }
    }

    public func dismissFailure() {
        if operation.failureMessage != nil { operation = .idle }
    }

    private func load() async {
        do {
            configuration = try await port.load()
            isLoaded = true
            loadFailure = nil
        } catch {
            loadFailure =
                "Tunnel settings could not be loaded. The existing file was preserved. " + ErrorText.message(for: error)
        }
        await refresh()
    }

    /// Runs one edit with its message, then reads the state again.
    @discardableResult
    func perform(
        _ message: String, _ work: @escaping @MainActor (TunnelsModel) async throws -> Void
    ) -> Task<Void, Never>? {
        guard canChange else { return nil }
        operation = .working(message)
        let task = Task {
            do {
                try await work(self)
                operation = .idle
            } catch {
                operation = .failed(message: ErrorText.message(for: error))
            }
            await refresh()
        }
        currentWork = task
        return task
    }
}
