import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// The Mailpit parts of the shared single-instance manager core: the `mail/` folder, its settings
/// file, the Mailpit definition, the default ports, and the inbox checks of a runtime update.
struct MailService: SingleServiceDescribing {
    let layout: MailLayout
    let dataRoot: URL
    let server: any MailServerProbing
    let store: MailSettingsStore

    init(layout: MailLayout, dataRoot: URL, server: any MailServerProbing) {
        self.layout = layout
        self.dataRoot = dataRoot
        self.server = server
        store = MailSettingsStore(layout: layout)
    }

    /// The items that a runtime update backs up, in order. Every name comes from `MailLayout`.
    static func updateItems(_ layout: MailLayout) -> [String] {
        [layout.settingsFile, layout.previousSettingsFile, layout.inboxDirectory].map(\.lastPathComponent)
    }

    var root: URL { layout.root }

    var messages: SingleServiceMessages { MailMessages.manager }

    var updateTransaction: RuntimeUpdateTransaction {
        RuntimeUpdateTransaction(
            root: layout.root, journalFile: layout.runtimeUpdateJournal,
            backupsDirectory: layout.runtimeBackupsDirectory, lockFile: layout.lockFile,
            names: Self.updateItems(layout), messages: MailMessages.update)
    }

    func loadSettings() throws -> MailSettings { try store.load() }

    func save(_ settings: MailSettings, replacing previous: MailRuntime?) throws {
        try store.save(settings, replacing: previous)
    }

    func definition(runtime: MailRuntime, ports: MailPorts) -> any ServiceDefinition {
        MailpitDefinition(runtime: runtime, ports: ports, layout: layout, dataRoot: dataRoot, server: server)
    }

    /// The first free SMTP port from 1025 and the first other free web port from 8025.
    func suggestPorts(using ports: LoopbackPortGuard) async throws -> MailPorts {
        let defaults = MailSettings.defaultPorts
        let smtp = try await ports.suggest(startingAt: defaults.smtp)
        let web = try await ports.suggest(startingAt: defaults.web, excluding: [smtp])
        return MailPorts(smtp: smtp, web: web)
    }

    func validateData(for runtime: MailRuntime) throws {
        try MailInbox(layout: layout).validate(for: runtime)
    }

    func adoptData(_ runtime: MailRuntime) throws {
        try MailInbox(layout: layout).adopt(runtime)
    }
}

extension MailSettings: SingleServiceSettings {}
extension MailRuntime: SingleServiceRuntime {}
extension MailPorts: SingleServicePorts {}
