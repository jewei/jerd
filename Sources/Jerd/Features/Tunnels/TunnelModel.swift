import AppKit
import Observation
import JerdCore

@MainActor @Observable
final class TunnelModel {
    var configuration = TunnelConfiguration()
    var states: [UUID: TunnelSnapshot] = [:]
    var isLoaded = false
    var isBusy = false
    var isShuttingDown = false
    var errorMessage: String?
    var copiedMessage: String?
    private(set) var stoppingIDs: Set<UUID> = []
    @ObservationIgnored private var stopTasks: [UUID: Task<Void, Never>] = [:]
    let directory = JSONConfigurationStore.applicationDirectory.appendingPathComponent("tunnels")
    @ObservationIgnored private lazy var manager = TunnelManager(directory: directory)
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var monitor: Task<Void, Never>?
    @ObservationIgnored private var copiedReset: Task<Void, Never>?

    var canChange: Bool { isLoaded && !isBusy && !isShuttingDown }
    var activeCount: Int { states.values.filter { $0.state.isActive || $0.processID != nil }.count }
    var runtimeMessage: String {
        configuration.runtime.map { "cloudflared \($0.version) is installed." }
            ?? "Install cloudflared in Runtimes, or choose a trusted local executable."
    }
    func canStop(_ tunnel: TunnelRegistration) -> Bool {
        isLoaded && !isShuttingDown && !stoppingIDs.contains(tunnel.id) && isActive(tunnel)
    }
    func state(_ tunnel: TunnelRegistration) -> TunnelState { states[tunnel.id]?.state ?? .stopped }
    func isActive(_ tunnel: TunnelRegistration) -> Bool {
        state(tunnel).isActive || states[tunnel.id]?.processID != nil
    }

    func load() {
        guard !isLoaded, !isBusy, !isShuttingDown else { return }
        isBusy = true
        errorMessage = nil
        work = Task {
            defer { isBusy = false }
            do {
                configuration = try await manager.load()
                isLoaded = true
                startMonitoring()
                for tunnel in configuration.tunnels where tunnel.startOnLaunch {
                    guard !isShuttingDown else { break }
                    do { try await manager.start(id: tunnel.id) }
                    catch { errorMessage = error.localizedDescription }
                }
                await refresh()
                startMonitoring()
            } catch {
                errorMessage = "Tunnel settings could not be loaded. The existing file was preserved. \(error.localizedDescription)"
            }
        }
    }

    func save(_ tunnel: TunnelRegistration, token: String?, completion: @escaping () -> Void) {
        perform {
            try await self.manager.save(tunnel, token: token)
            await self.refresh()
            completion()
        }
    }
    func suggestedPort() async throws -> UInt16 { try await manager.suggestedPort() }
    func start(_ tunnel: TunnelRegistration) { perform { try await self.manager.start(id: tunnel.id) } }
    func stop(_ tunnel: TunnelRegistration) {
        guard canStop(tunnel) else { return }
        stoppingIDs.insert(tunnel.id)
        stopTasks[tunnel.id] = Task {
            defer { stoppingIDs.remove(tunnel.id); stopTasks[tunnel.id] = nil }
            do { try await manager.stop(id: tunnel.id) }
            catch { errorMessage = error.localizedDescription }
            await refresh()
        }
    }
    func remove(_ tunnel: TunnelRegistration, completion: @escaping () -> Void) {
        perform {
            try await self.manager.stop(id: tunnel.id)
            try await self.manager.remove(id: tunnel.id)
            completion()
        }
    }
    func registerUpdatedRuntime(_ runtime: TunnelRuntime) async throws {
        guard canChange else { throw JerdError.unavailable("Wait for the current tunnel operation to finish.") }
        isBusy = true
        defer { isBusy = false }
        do { try await manager.registerRuntime(runtime); await refresh() }
        catch { await refresh(); throw error }
    }
    func chooseRuntime() {
        guard canChange else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose a trusted cloudflared executable"
        panel.message = "Jerd will run this file to check its version. Select a file that you trust."
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use executable"
        guard panel.runModal() == .OK, let executable = panel.url else { return }
        perform {
            let runtime = try await self.manager.inspectRuntime(executable: executable)
            try await self.manager.registerRuntime(runtime)
        }
    }
    func log(_ tunnel: TunnelRegistration) async throws -> String { try await manager.log(id: tunnel.id) }
    func copyURL(_ tunnel: TunnelRegistration) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("https://\(tunnel.hostname)", forType: .string)
        copiedMessage = "Public address copied."
        copiedReset?.cancel()
        copiedReset = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.copiedMessage = nil
        }
    }
    func open(_ tunnel: TunnelRegistration) {
        if let url = URL(string: "https://\(tunnel.hostname)") { NSWorkspace.shared.open(url) }
    }
    func openCloudflare() {
        NSWorkspace.shared.open(URL(string: "https://one.dash.cloudflare.com/")!)
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard canChange else { return }
        isBusy = true
        errorMessage = nil
        work = Task {
            defer { isBusy = false }
            do { try await action() }
            catch { errorMessage = error.localizedDescription }
            await refresh()
        }
    }
    private func refresh() async {
        let latestConfiguration = await manager.configurationSnapshot()
        let snapshots = await manager.snapshots()
        let latestStates = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.registration.id, $0) })
        if configuration != latestConfiguration { configuration = latestConfiguration }
        if states != latestStates { states = latestStates }
    }
    private func startMonitoring() {
        monitor?.cancel()
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.refresh()
            }
        }
    }
    func shutdown() async -> Bool {
        isShuttingDown = true
        do {
            if isLoaded { try await manager.stopAll() }
            await work?.value
            for task in stopTasks.values { await task.value }
            // A load in progress can finish after the first stop request.
            if isLoaded { try await manager.stopAll() }
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
    func resumeAfterCancelledQuit() {
        isShuttingDown = false
        if isLoaded { startMonitoring() }
    }
}

extension TunnelState {
    var isActive: Bool {
        switch self {
        case .starting, .connected, .reconnecting, .stopping: true
        case .stopped, .failed: false
        }
    }
    var tone: StatusTone {
        switch self {
        case .connected: .ready
        case .starting, .reconnecting, .stopping: .busy
        case .stopped: .idle
        case .failed: .failed
        }
    }
}
