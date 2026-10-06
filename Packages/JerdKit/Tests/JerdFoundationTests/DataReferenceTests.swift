import Foundation
import JerdFoundation
import Testing

/// Fixed review foundation-process-r1 L14: `Docs/Reference.md` names every path of `DataLayout`.
@Suite struct DataReferenceTests {
    private static let root = URL(fileURLWithPath: "/data/Jerd")
    private static let id = UUID(uuidString: "1F3A0000-0000-0000-0000-00000000000A") ?? UUID()

    /// The repository copy of the data reference, found from this source file.
    private static func reference() throws -> String {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { folder.deleteLastPathComponent() }
        return try String(contentsOf: folder.appendingPathComponent("Docs/Reference.md"), encoding: .utf8)
    }

    /// Every path of the layout, relative to the root, with `<UUID>` for an instance ID.
    private static func layoutPaths() -> [String] {
        let layout = DataLayout(root: root)
        let environment = layout.environment
        let runtimes = layout.runtimes
        let database = layout.databases.instance(id)
        let tunnel = layout.tunnels.instance(id)
        let mail = layout.mail
        let storage = layout.storage
        let urls: [URL] = [
            layout.configurationFile, layout.previousConfigurationFile, layout.binDirectory,
            layout.shellBackupsDirectory, environment.installationIDFile, environment.caddyConfigurationFile,
            environment.fpmConfigurationFile, environment.phpINIFile, environment.prepareCAFile,
            environment.phpCABundleFile, environment.emptyINIDirectory, environment.rootCertificateFile,
            environment.caddyLogFile, environment.fpmLogFile, environment.recoveryLockFile,
            environment.phpRuntimeDirectory(id), environment.preflightDirectory(id),
            environment.processRecord(id).recordFile, runtimes.developmentRuntimesDirectory, runtimes.cliToolsFile,
            runtimes.cliINIFile, runtimes.cliLocalTLSINIFile, runtimes.cliCABundleFile, runtimes.cliEmptyINIDirectory,
            runtimes.bootstrapInspectionDirectory, runtimes.inspectionDirectory, runtimes.managedRuntimesDirectory,
            runtimes.databaseRuntimesDirectory, runtimes.mailRuntimesDirectory, runtimes.storageRuntimesDirectory,
            layout.databases.servicesFile, layout.databases.previousServicesFile, database.lockFile,
            database.activeRunFile, database.runtimeIdentityFile, database.initializedMarkerFile,
            database.credentialsFile, database.removedRegistrationFile, database.logFile, database.previousLogFile,
            database.dataDirectory, mail.settingsFile, mail.previousSettingsFile, mail.lockFile, mail.activeRunFile,
            mail.logFile, mail.previousLogFile, mail.inboxDatabaseFile, mail.runtimeIdentityFile,
            mail.initializedMarkerFile, mail.runtimeUpdateJournal, mail.runtimeBackupsDirectory,
            storage.settingsFile, storage.previousSettingsFile, storage.lockFile, storage.activeRunFile,
            storage.logFile, storage.previousLogFile, storage.runtimeIdentityFile, storage.initializedMarkerFile,
            storage.credentialsFile, storage.accessKeyFile, storage.secretKeyFile, storage.dataDirectory,
            storage.formatFile, storage.runtimeUpdateJournal, storage.runtimeBackupsDirectory,
            layout.tunnels.settingsFile, layout.tunnels.previousSettingsFile, tunnel.lockFile, tunnel.activeRunFile,
            tunnel.configurationFile, tunnel.logFile, tunnel.previousLogFile, tunnel.homeDirectory,
        ]
        return urls.map { url in
            String(url.path.dropFirst(root.path.count + 1)).replacingOccurrences(of: id.uuidString, with: "<UUID>")
        }
    }

    @Test func theReferenceNamesEveryLayoutPath() throws {
        let text = try Self.reference()
        let missing = Self.layoutPaths().filter { !text.contains("`\($0)`") }
        #expect(missing.isEmpty, "Docs/Reference.md does not name: \(missing)")
    }
}
