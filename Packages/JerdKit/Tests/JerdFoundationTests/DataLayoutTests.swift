import Foundation
import JerdFoundation
import Testing

@Suite struct DataLayoutTests {
    private let root = URL(fileURLWithPath: "/data/Jerd")
    private let id = UUID(uuidString: "1F3A0000-0000-0000-0000-00000000000A") ?? UUID()

    private func relative(_ url: URL) -> String {
        String(url.path.dropFirst(root.path.count + 1))
    }

    @Test func theCurrentUserRootIsApplicationSupportJerd() {
        let expected = FileManager.default.homeDirectoryForCurrentUser.path + "/Library/Application Support/Jerd"
        #expect(DataLayout.currentUser().root.path == expected)
    }

    @Test func topLevelAndWebPathsMatchTheInstalledLayout() {
        let layout = DataLayout(root: root)
        let environment = layout.environment
        let pairs: [(URL, String)] = [
            (layout.configurationFile, "configuration.json"),
            (layout.previousConfigurationFile, "configuration.previous.json"),
            (layout.binDirectory, "bin"), (layout.shellBackupsDirectory, "shell-backups"),
            (environment.installationIDFile, "environment/installation-id"),
            (environment.caddyConfigurationFile, "environment/configuration/caddy.json"),
            (environment.fpmConfigurationFile, "environment/configuration/php-fpm.conf"),
            (environment.phpINIFile, "environment/configuration/php.ini"),
            (environment.prepareCAFile, "environment/configuration/prepare-ca.json"),
            (environment.phpCABundleFile, "environment/configuration/php-ca.pem"),
            (environment.emptyINIDirectory, "environment/configuration/empty-ini"),
            (environment.rootCertificateFile, "environment/certificates/pki/authorities/jerd/root.crt"),
            (environment.caddyLogFile, "environment/logs/caddy.log"),
            (environment.fpmLogFile, "environment/logs/fpm.log"),
            (environment.recoveryLockFile, "environment/processes/recovery.lock"),
            (environment.phpRuntimeDirectory(id), "environment/php/\(id.uuidString)"),
            (environment.preflightDirectory(id), "environment/preflight-\(id.uuidString)"),
            (layout.runtimes.cliToolsFile, "runtimes/cli-tools.json"),
            (layout.runtimes.cliINIFile, "runtimes/configuration/cli.ini"),
            (layout.runtimes.cliLocalTLSINIFile, "runtimes/configuration/cli-local-tls.ini"),
            (layout.runtimes.cliCABundleFile, "runtimes/configuration/php-ca.pem"),
            (layout.runtimes.cliEmptyINIDirectory, "runtimes/configuration/empty-ini"),
            (layout.runtimes.bootstrapInspectionDirectory, "runtimes/inspection/empty-ini"),
            (layout.runtimes.inspectionDirectory, "runtime-inspection/empty-ini"),
            (layout.runtimes.managedRuntimesDirectory, "runtime-updates"),
            (layout.runtimes.databaseRuntimesDirectory, "database-runtimes"),
            (layout.runtimes.mailRuntimesDirectory, "mail-runtimes"),
            (layout.runtimes.storageRuntimesDirectory, "storage-runtimes"),
        ]
        for (url, expected) in pairs { #expect(relative(url) == expected) }
    }

    @Test func servicePathsMatchTheInstalledLayout() {
        let layout = DataLayout(root: root)
        let database = layout.databases.instance(id)
        let tunnel = layout.tunnels.instance(id)
        let pairs: [(URL, String)] = [
            (layout.databases.servicesFile, "databases/services.json"),
            (layout.databases.previousServicesFile, "databases/services.previous.json"),
            (database.lockFile, "databases/instances/\(id.uuidString)/service.lock"),
            (database.credentialsFile, "databases/instances/\(id.uuidString)/credentials.json"),
            (database.removedRegistrationFile, "databases/instances/\(id.uuidString)/removed-registration.json"),
            (database.previousLogFile, "databases/instances/\(id.uuidString)/server.previous.log"),
            (database.dataDirectory, "databases/instances/\(id.uuidString)/data"),
            (layout.mail.settingsFile, "mail/settings.json"),
            (layout.mail.inboxDatabaseFile, "mail/inbox/messages.sqlite"),
            (layout.mail.runtimeIdentityFile, "mail/inbox/runtime.json"),
            (layout.mail.initializedMarkerFile, "mail/inbox/initialized.json"),
            (layout.mail.runtimeUpdateJournal, "mail/runtime-update.json"),
            (layout.mail.runtimeBackupsDirectory, "mail/runtime-backups"),
            (layout.storage.credentialsFile, "storage/credentials.json"),
            (layout.storage.accessKeyFile, "storage/access-key"), (layout.storage.secretKeyFile, "storage/secret-key"),
            (layout.storage.formatFile, "storage/data/.rustfs.sys/format.json"),
            (layout.storage.initializedMarkerFile, "storage/initialized.json"),
            (layout.tunnels.settingsFile, "tunnels/settings.json"),
            (tunnel.configurationFile, "tunnels/instances/\(id.uuidString)/config.yml"),
            (tunnel.homeDirectory, "tunnels/instances/\(id.uuidString)/home"),
        ]
        for (url, expected) in pairs { #expect(relative(url) == expected) }
    }

    @Test func recordLocationsUseTheCompatibleIDsAndLocks() {
        let layout = DataLayout(root: root)
        let records = [
            layout.mail.record, layout.storage.record, layout.databases.instance(id).record,
            layout.tunnels.instance(id).record, layout.environment.processRecord(id),
        ]
        #expect(
            records.map(\.id) == [
                "Mail", "Storage", "Database/\(id.uuidString)", "Tunnel/\(id.uuidString)",
                "Web/\(id.uuidString)",
            ])
        #expect(
            records.map { relative($0.recordFile) } == [
                "mail/active-run.json", "storage/active-run.json",
                "databases/instances/\(id.uuidString)/active-run.json",
                "tunnels/instances/\(id.uuidString)/active-run.json", "environment/processes/\(id.uuidString).json",
            ])
        #expect(
            records.map { relative($0.lockFile) } == [
                "mail/service.lock", "storage/service.lock", "databases/instances/\(id.uuidString)/service.lock",
                "tunnels/instances/\(id.uuidString)/service.lock", "environment/processes/recovery.lock",
            ])
        #expect(records.shuffled().sorted() == records)
    }

    @Test func recordScansCoverEveryFamilyInListOrder() {
        let layout = DataLayout(root: root)
        let scans = layout.recordScans
        #expect(scans.map(\.family) == RecordFamily.allCases)
        #expect(
            scans.map { relative($0.directory) } == [
                "mail", "storage", "databases/instances", "tunnels/instances", "environment/processes",
            ])
        guard case .folderPerInstance(let locate) = scans[2].arrangement else {
            Issue.record("Databases must use one folder per instance.")
            return
        }
        let found = root.appendingPathComponent("databases/instances/\(id.uuidString.lowercased())")
        #expect(locate(id, found).recordFile == found.appendingPathComponent("active-run.json"))
    }
}
