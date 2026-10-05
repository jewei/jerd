import Foundation

/// The single source of every path under Jerd's data root, `~/Library/Application Support/Jerd`.
///
/// Every path is part of the compatibility contract with installed copies. Tests inject a
/// temporary root.
public struct DataLayout: Hashable, Sendable {
    /// The data root folder (mode 0700).
    public let root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    /// The layout of the current user: `~/Library/Application Support/Jerd`.
    public static func currentUser() -> DataLayout {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return DataLayout(root: home.folder("Library").folder("Application Support").folder("Jerd"))
    }

    /// The site configuration, encoded with `JSONFileFormat.settings`.
    public var configurationFile: URL { root.file("configuration.json") }
    /// The bytes of the site configuration before the last save.
    public var previousConfigurationFile: URL { root.file("configuration.previous.json") }
    /// The optional command-line launcher and its `php`, `composer`, and `laravel` links.
    public var binDirectory: URL { root.folder("bin") }
    /// Shell file backups: `shell-backups/<YYYYmmdd-HHMMSS-ffffff>/`.
    public var shellBackupsDirectory: URL { root.folder("shell-backups") }

    public var environment: EnvironmentLayout { EnvironmentLayout(root: root.folder("environment")) }
    public var runtimes: RuntimeLayout { RuntimeLayout(root: root) }
    public var databases: DatabasesLayout { DatabasesLayout(root: root.folder("databases")) }
    public var mail: MailLayout { MailLayout(root: root.folder("mail")) }
    public var storage: StorageLayout { StorageLayout(root: root.folder("storage")) }
    public var tunnels: TunnelsLayout { TunnelsLayout(root: root.folder("tunnels")) }

    /// Every place where an active-run record can be, in the order that recovery lists them.
    public var recordScans: [RecordScan] {
        let databases = databases
        let tunnels = tunnels
        let environment = environment
        return [
            RecordScan(family: .mail, directory: mail.root, arrangement: .single(mail.record)),
            RecordScan(family: .storage, directory: storage.root, arrangement: .single(storage.record)),
            RecordScan(
                family: .database, directory: databases.instancesDirectory,
                arrangement: .folderPerInstance { id, folder in
                    DatabaseInstanceLayout(id: id, root: folder).record
                }),
            RecordScan(
                family: .tunnel, directory: tunnels.instancesDirectory,
                arrangement: .folderPerInstance { id, folder in
                    TunnelInstanceLayout(id: id, root: folder).record
                }),
            RecordScan(
                family: .web, directory: environment.processesDirectory,
                arrangement: .filePerInstance(fileExtension: "json") { id, file in
                    RecordLocation(family: .web, instance: id, recordFile: file, lockFile: environment.recoveryLockFile)
                }),
        ]
    }
}
