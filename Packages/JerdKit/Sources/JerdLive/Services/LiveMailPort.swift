import JerdFoundation
import JerdMail
import JerdRuntimes
import JerdUI

/// The Mail port on the one `MailManager`. Its load installs an embedded Mailpit when no runtime
/// is saved; a failed bundled setup leaves the load usable. An app that does not embed Mailpit
/// installs it on demand, only after a user action, and its load downloads nothing.
package struct LiveMailPort: MailPort {
    let manager: any MailManaging
    let runtimes: any ServiceRuntimeSource
    let layout: MailLayout
    let setup: BundledSetupRecord
    /// The on-demand installation, or nil in a port without one: it offers nothing then.
    let onDemand: MailRuntimeInstaller?

    package init(
        manager: any MailManaging, runtimes: any ServiceRuntimeSource, layout: MailLayout,
        setup: BundledSetupRecord = BundledSetupRecord(), onDemand: MailRuntimeInstaller? = nil
    ) {
        self.manager = manager
        self.runtimes = runtimes
        self.layout = layout
        self.setup = setup
        self.onDemand = onDemand
    }

    package init(domain: LiveDomain) {
        self.init(
            manager: domain.mail, runtimes: BundledServiceRuntimes(bootstrap: domain.bootstrap),
            layout: domain.layout.mail, onDemand: MailRuntimeInstaller(domain: domain))
    }

    package func runtimeOffer() async -> ServiceRuntimeOffer? {
        await onDemand?.offer()
    }

    package func installRuntime(
        progress: @escaping @Sendable (RuntimeInstallProgress) -> Void
    ) async throws -> MailRuntime {
        guard let onDemand else {
            throw JerdError.unavailable("This copy of Jerd cannot install Mailpit. Install it in Runtimes.")
        }
        ServiceActivityLog.request("Install", "the Mailpit runtime")
        return try await onDemand.install(progress: progress)
    }

    /// Loads the settings first: corrupt settings fail here and nothing is installed. A saved
    /// runtime (also one that an earlier copy installed in `mail-runtimes/`) stays in use, and the
    /// inbox is never touched.
    package func load() async throws -> MailSnapshot {
        if try await manager.load().runtime == nil {
            do {
                if let embedded = try await runtimes.mailRuntime() {
                    try await manager.registerRuntime(embedded)
                }
                await setup.record(nil)
            } catch {
                BundledServiceRuntimes.report(error, service: "mail")
                await setup.record(BundledServiceRuntimes.message(for: error))
            }
        }
        return await manager.snapshot()
    }

    package func runtimeSetupFailure() async -> String? {
        await setup.failure
    }

    package func snapshot() async -> MailSnapshot {
        await manager.snapshot()
    }

    package func files() async -> ServiceFiles {
        ServiceFilesProbe.files(dataFolder: layout.inboxDirectory, log: layout.logFile)
    }

    package func start() async throws {
        ServiceActivityLog.request("Start", "mail")
        try await manager.start()
    }

    package func stop() async throws {
        ServiceActivityLog.request("Stop", "mail")
        try await manager.stop()
    }

    package func sendTestEmail() async throws {
        try await manager.sendTestEmail()
    }

    package func suggestedPorts() async throws -> MailPorts {
        try await manager.suggestedPorts()
    }

    package func edit(ports: MailPorts) async throws {
        try await manager.edit(ports: ports)
    }
}
