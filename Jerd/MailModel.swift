import AppKit
import Observation
import JerdCore

@MainActor @Observable
final class MailModel {
    var configuration = MailConfiguration()
    var state = MailState.stopped
    var processID: Int32?
    var isLoaded = false
    var isBusy = false
    var isShuttingDown = false
    var errorMessage: String?
    var runtimeMessage = "Preparing Mailpit…"
    var testMessage: String?
    let directory = JSONConfigurationStore.applicationDirectory.appendingPathComponent("mail")
    @ObservationIgnored private lazy var manager = MailManager(directory: directory)
    private var work: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    var paths: MailPaths { MailPaths(root: directory) }
    var canChange: Bool { isLoaded && !isBusy && !isShuttingDown }

    func load() {
        guard !isBusy, !isShuttingDown else { return }
        isBusy = true
        errorMessage = nil
        work = Task {
            defer { isBusy = false }
            do {
                configuration = try await manager.load()
                isLoaded = true
                if configuration.runtime == nil, let resources = Bundle.main.resourceURL {
                    do {
                        let runtime = try await BundledMailRuntime().install(
                            from: resources.appendingPathComponent("MailRuntime"),
                            into: JSONConfigurationStore.applicationDirectory.appendingPathComponent("mail-runtimes"))
                        if configuration.runtime == nil { try await manager.registerRuntime(runtime) }
                        runtimeMessage = "Mailpit is installed."
                    } catch { runtimeMessage = "Mailpit setup failed: \(error.localizedDescription)" }
                }
                if let runtime = configuration.runtime { runtimeMessage = "Mailpit \(runtime.version) is installed." }
                await refresh()
                startMonitoring()
            } catch {
                errorMessage = error.localizedDescription
                runtimeMessage = "Mail settings could not be loaded. The existing file was preserved."
            }
        }
    }

    func start() { perform { try await self.manager.start() } }
    func updateRuntime(_ runtime: MailRuntime) async throws {
        guard canChange else { throw JerdError.unavailable("Wait for the current mail operation to finish.") }
        isBusy = true; defer { isBusy = false }
        do { try await manager.updateRuntime(runtime); await refresh() }
        catch { await refresh(); throw error }
    }
    func stop() { perform { try await self.manager.stop() } }
    func edit(smtp: UInt16, web: UInt16, completion: @escaping () -> Void) {
        perform { try await self.manager.edit(smtpPort: smtp, webPort: web); completion() }
    }
    func suggestPorts() async throws -> (smtp: UInt16, web: UInt16) { try await manager.suggestedPorts() }
    func sendTestEmail() {
        testMessage = nil
        perform {
            try await self.manager.sendTestEmail()
            self.testMessage = "Test email captured. Open the inbox to view it."
        }
    }
    private func perform(_ action: @escaping @MainActor () async throws -> Void) {
        guard canChange else { return }
        isBusy = true
        errorMessage = nil
        work = Task {
            defer { isBusy = false }
            do { try await action() } catch { errorMessage = error.localizedDescription }
            await refresh()
        }
    }
    func openInbox() {
        guard state == .running else { return }
        NSWorkspace.shared.open(configuration.inboxURL)
    }
    func copyLaravelSettings() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(configuration.laravelSettings, forType: .string)
    }
    func showData() {
        if !NSWorkspace.shared.open(paths.inbox) { errorMessage = "Start the mail service once to create its inbox." }
    }
    func openLog() {
        if !NSWorkspace.shared.open(paths.log) { errorMessage = "The mail log is not available yet." }
    }
    private func refresh() async {
        let snapshot = await manager.snapshot()
        configuration = snapshot.configuration
        state = snapshot.state
        processID = snapshot.processID
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
        await work?.value
        do {
            if isLoaded { try await manager.stop() }
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
