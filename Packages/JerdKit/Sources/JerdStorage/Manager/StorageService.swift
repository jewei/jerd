import Foundation
import JerdFoundation
import JerdProcess
import JerdServiceKit

/// The RustFS parts of the shared single-instance manager core: the `storage/` folder, its
/// settings file, the RustFS definition, the default ports, and the data checks of a runtime update.
struct StorageService: SingleServiceDescribing {
    let layout: StorageLayout
    let dataRoot: URL
    let launch: StorageLaunch
    let makeSession: @Sendable () -> S3Session
    let now: @Sendable () -> Date
    let store: StorageSettingsStore

    init(
        layout: StorageLayout, dataRoot: URL, launch: StorageLaunch,
        makeSession: @escaping @Sendable () -> S3Session, now: @escaping @Sendable () -> Date
    ) {
        self.layout = layout
        self.dataRoot = dataRoot
        self.launch = launch
        self.makeSession = makeSession
        self.now = now
        store = StorageSettingsStore(layout: layout)
    }

    /// The items that a runtime update backs up, in order. Every name comes from `StorageLayout`.
    static func updateItems(_ layout: StorageLayout) -> [String] {
        [
            layout.settingsFile, layout.previousSettingsFile, layout.dataDirectory, layout.runtimeIdentityFile,
            layout.initializedMarkerFile, layout.credentialsFile, layout.accessKeyFile, layout.secretKeyFile,
        ].map(\.lastPathComponent)
    }

    var root: URL { layout.root }

    var messages: SingleServiceMessages { StorageMessages.manager }

    var updateTransaction: RuntimeUpdateTransaction {
        RuntimeUpdateTransaction(
            root: layout.root, journalFile: layout.runtimeUpdateJournal,
            backupsDirectory: layout.runtimeBackupsDirectory, lockFile: layout.lockFile,
            names: Self.updateItems(layout), messages: StorageMessages.update)
    }

    func loadSettings() throws -> StorageSettings { try store.load() }

    func save(_ settings: StorageSettings, replacing previous: StorageRuntime?) throws {
        try store.save(settings, replacing: previous)
    }

    func definition(runtime: StorageRuntime, ports: StoragePorts) -> any ServiceDefinition {
        RustFSDefinition(
            runtime: runtime, ports: ports, layout: layout, dataRoot: dataRoot, launch: launch,
            makeSession: makeSession, now: now)
    }

    /// The first free API port from 9000 and the first other free console port from 9001.
    func suggestPorts(using ports: LoopbackPortGuard) async throws -> StoragePorts {
        let defaults = StorageSettings.defaultPorts
        let api = try await ports.suggest(startingAt: defaults.api)
        let console = try await ports.suggest(startingAt: defaults.console, excluding: [api])
        return StoragePorts(api: api, console: console)
    }

    func validateData(for runtime: StorageRuntime) throws {
        try StorageData(layout: layout).validate(for: runtime)
    }

    func adoptData(_ runtime: StorageRuntime) throws {
        try StorageData(layout: layout).adopt(runtime)
    }

    /// The updated service must list every complete bucket.
    func verifyUpdatedService(_ settings: StorageSettings) async throws {
        let complete = Set(settings.buckets.filter(\.setupComplete).map(\.name))
        guard complete.isSubset(of: launch.names) else { throw StorageMessages.bucketsMissingAfterUpdate }
    }
}

extension StorageSettings: SingleServiceSettings {}
extension StorageRuntime: SingleServiceRuntime {}
extension StoragePorts: SingleServicePorts {}
