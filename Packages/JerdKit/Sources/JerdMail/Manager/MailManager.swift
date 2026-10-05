import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// Owns the one local Mailpit inbox, independently of sites and databases.
///
/// Rules:
/// - Every call except `load` and `snapshot` requires loaded settings.
/// - One operation runs at a time. Exit detection in `snapshot()` is not an operation: it never
///   waits for a stop, so it never blocks Stop or Quit.
/// - While a runtime update needs recovery, only `load`, `start`, and `stop` run; `load` and
///   `start` recover it first.
/// - Stop and Quit keep every captured message.
public actor MailManager {
    /// The items that a runtime update backs up, in order.
    static let updateItems = [ServiceFileName.settings, ServiceFileName.previousSettings, "inbox"]

    public nonisolated let layout: MailLayout
    let dataRoot: URL
    let effects: ServiceEffects
    let server: any MailServerProbing
    let store: MailSettingsStore
    let transaction: RuntimeUpdateTransaction
    var settings = MailSettings()
    /// The managed instance. It exists once a runtime is saved.
    var instance: ManagedInstance?
    var loaded = false
    var busy = false

    /// - Parameters:
    ///   - layout: the data layout; the inbox lives in `layout.mail`.
    ///   - server: the readiness answers of Mailpit. The default asks the real service.
    public init(layout: DataLayout, effects: ServiceEffects, server: (any MailServerProbing)? = nil) {
        let mail = layout.mail
        self.layout = mail
        dataRoot = layout.root
        self.effects = effects
        self.server = server ?? MailServerProbe(commands: effects.commands, workingDirectory: mail.root)
        store = MailSettingsStore(layout: mail)
        transaction = RuntimeUpdateTransaction(
            root: mail.root, journalFile: mail.runtimeUpdateJournal, backupsDirectory: mail.runtimeBackupsDirectory,
            lockFile: mail.lockFile, names: Self.updateItems, messages: MailMessages.update)
    }

    /// Loads the settings once, creates `mail/` (mode 0700), and recovers an unfinished runtime
    /// update. Later calls return the loaded settings.
    public func load() async throws -> MailSettings {
        guard !loaded else { return settings }
        try begin(allowingRecovery: true)
        defer { busy = false }
        try OwnedDirectory.create(layout.root)
        settings = try store.load()
        if let runtime = settings.runtime { instance = makeInstance(runtime: runtime, ports: settings.ports) }
        try await recoverPendingUpdate()
        loaded = true
        return settings
    }

    /// The settings and the state. It also detects an unexpected exit of Mailpit.
    public func snapshot() async -> MailSnapshot {
        let state = await instance?.refresh() ?? .stopped
        return MailSnapshot(settings: settings, state: state)
    }

    // MARK: Helpers

    /// Runs `body` as the one operation in progress.
    func exclusive<Result>(allowingRecovery: Bool = false, _ body: () async throws -> Result) async throws -> Result {
        guard loaded else { throw MailMessages.notLoaded }
        try begin(allowingRecovery: allowingRecovery)
        defer { busy = false }
        return try await body()
    }

    private func begin(allowingRecovery: Bool) throws {
        guard !busy else { throw JerdError.unavailable(MailMessages.busy) }
        guard allowingRecovery || !transaction.isPending else { throw MailMessages.updatePending }
        busy = true
    }

    func definition(runtime: MailRuntime, ports: MailPorts) -> MailpitDefinition {
        MailpitDefinition(runtime: runtime, ports: ports, layout: layout, dataRoot: dataRoot, server: server)
    }

    func makeInstance(runtime: MailRuntime, ports: MailPorts) -> ManagedInstance {
        ManagedInstance(definition: definition(runtime: runtime, ports: ports), effects: effects)
    }

    /// Restores an unfinished runtime update. Without a journal it does nothing.
    func recoverPendingUpdate() async throws {
        guard transaction.isPending else { return }
        guard let instance else { throw MailMessages.recoveryWithoutRuntime }
        try await transaction.recoverIfNeeded(on: instance, reload: { try await self.reloadDefinition() })
    }

    /// Reloads the saved settings, for example after a restore, and returns their definition.
    func reloadDefinition() throws -> any ServiceDefinition {
        let restored = try store.load()
        guard let runtime = restored.runtime else { throw MailMessages.recoveryWithoutRuntime }
        settings = restored
        return definition(runtime: runtime, ports: restored.ports)
    }
}
