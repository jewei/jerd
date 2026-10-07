import JerdFoundation
import JerdMail
import JerdUI

/// The Mail port on the one `MailManager`. Its load installs the bundled Mailpit when no runtime
/// is saved; a failed bundled setup leaves the load usable.
package struct LiveMailPort: MailPort {
    let manager: any MailManaging
    let runtimes: any ServiceRuntimeSource
    let layout: MailLayout
    let setup: BundledSetupRecord

    package init(
        manager: any MailManaging, runtimes: any ServiceRuntimeSource, layout: MailLayout,
        setup: BundledSetupRecord = BundledSetupRecord()
    ) {
        self.manager = manager
        self.runtimes = runtimes
        self.layout = layout
        self.setup = setup
    }

    package init(domain: LiveDomain) {
        self.init(
            manager: domain.mail, runtimes: BundledServiceRuntimes(bootstrap: domain.bootstrap),
            layout: domain.layout.mail)
    }

    /// Loads the settings first: corrupt settings fail here and nothing is installed.
    package func load() async throws -> MailSnapshot {
        if try await manager.load().runtime == nil {
            do {
                try await manager.registerRuntime(try await runtimes.mailRuntime())
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
